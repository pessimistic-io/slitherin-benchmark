// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IOmniseaUniversalONFT721.sol";
import "./NonblockingLzApp.sol";
import "./IOmniseaRemoteERC721.sol";
import "./IOmniseaDropsFactory.sol";
import "./OmniseaERC721Proxy.sol";
import "./ERC165.sol";
import "./ReentrancyGuard.sol";
import {BasicCollectionParams} from "./ERC721Structs.sol";

contract OmniseaUniversalONFT721 is NonblockingLzApp, ERC165, ReentrancyGuard, IOmniseaUniversalONFT721 {
    uint16 public constant FUNCTION_TYPE_SEND = 1;
    uint16 private immutable _chainId;
    uint256 public fixedFee;
    address internal revenueManager;
    mapping(address => bytes32) public collectionToId;
    mapping(bytes32 => address) public idToCollection;
    IOmniseaDropsFactory private _factory;

    struct StoredCredit {
        uint16 srcChainId;
        address collection;
        address toAddress;
        uint256 index;
        bool creditsRemain;
    }

    uint256 public minGasToTransferAndStore; // min amount of gas required to transfer, and also store the payload
    mapping(uint16 => uint256) public dstChainIdToBatchLimit;
    mapping(uint16 => uint256) public dstChainIdToTransferGas; // per transfer amount of gas required to mint/transfer on the dst
    mapping(bytes32 => StoredCredit) public storedCredits;

    constructor(uint16 chainId_, address _lzEndpoint, uint256 _minGasToTransferAndStore) NonblockingLzApp(_lzEndpoint) {
        minGasToTransferAndStore = _minGasToTransferAndStore;
        revenueManager = address(0x61104fBe07ecc735D8d84422c7f045f8d29DBf15);
        fixedFee = 250000000000000;
        _chainId = chainId_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOmniseaUniversalONFT721).interfaceId || super.supportsInterface(interfaceId);
    }

    function setFixedFee(uint256 fee) external onlyOwner {
        fixedFee = fee;
    }

    function estimateSendFee(uint16 _dstChainId, bytes memory _toAddress, uint _tokenId, bool _useZro, bytes memory _adapterParams, BasicCollectionParams memory _collectionParams) public view virtual override returns (uint nativeFee, uint zroFee) {
        return estimateSendBatchFee(_dstChainId, _toAddress, _toSingletonArray(_tokenId), _useZro, _adapterParams, _collectionParams);
    }

    function estimateSendBatchFee(uint16 _dstChainId, bytes memory _toAddress, uint[] memory _tokenIds, bool _useZro, bytes memory _adapterParams, BasicCollectionParams memory _collectionParams) public view virtual override returns (uint nativeFee, uint zroFee) {
        bytes memory payload = abi.encode(_toAddress, _toAddress, _tokenIds, _collectionParams);
        (nativeFee, zroFee) = lzEndpoint.estimateFees(_dstChainId, address(this), payload, _useZro, _adapterParams);
        nativeFee += fixedFee;
    }

    function sendFrom(address _from, uint16 _dstChainId, bytes memory _toAddress, uint _tokenId, address payable _refundAddress, address _zroPaymentAddress, bytes memory _adapterParams, BasicCollectionParams memory _collectionParams) public payable virtual override nonReentrant {
        _send(_from, _dstChainId, _toAddress, _toSingletonArray(_tokenId), _refundAddress, _zroPaymentAddress, _adapterParams, _collectionParams);
    }

    function sendBatchFrom(address _from, uint16 _dstChainId, bytes memory _toAddress, uint[] memory _tokenIds, address payable _refundAddress, address _zroPaymentAddress, bytes memory _adapterParams, BasicCollectionParams memory _collectionParams) public payable virtual override nonReentrant {
        _send(_from, _dstChainId, _toAddress, _tokenIds, _refundAddress, _zroPaymentAddress, _adapterParams, _collectionParams);
    }

    function _send(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint[] memory _tokenIds,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        BasicCollectionParams memory _collectionParams
    ) internal virtual {
        require(_tokenIds.length > 0);
        require(_tokenIds.length <= dstChainIdToBatchLimit[_dstChainId]);

        bytes32 collectionId = collectionToId[msg.sender];
        if (collectionId == bytes32(0)) {
            require(_factory.drops(msg.sender));
            collectionId = keccak256(abi.encode(msg.sender, _chainId));
            idToCollection[collectionId] = msg.sender;
            collectionToId[msg.sender] = collectionId;
        }

        for (uint i = 0; i < _tokenIds.length; i++) {
            _debitFrom(_from, _dstChainId, msg.sender, _toAddress, _tokenIds[i]);
        }

        bytes memory payload = abi.encode(_toAddress, _tokenIds, _collectionParams, collectionId);
        _checkGasLimit(_dstChainId, FUNCTION_TYPE_SEND, _adapterParams, dstChainIdToTransferGas[_dstChainId] * _tokenIds.length);
        (uint nativeFee) = _payONFTFee(msg.value);
        _lzSend(_dstChainId, payload, _refundAddress, _zroPaymentAddress, _adapterParams, nativeFee);
        emit SendToChain(_dstChainId, _from, _toAddress, _tokenIds);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64, /*_nonce*/
        bytes memory _payload
    ) internal virtual override {
        (bytes memory toAddressBytes, uint[] memory tokenIds, BasicCollectionParams memory _collectionParams, bytes32 _collectionId) = abi.decode(_payload, (bytes, uint[], BasicCollectionParams, bytes32));

        address toAddress;
        assembly {
            toAddress := mload(add(toAddressBytes, 20))
        }

        address collection = idToCollection[_collectionId];
        if (collection == address(0)) {
            OmniseaERC721Proxy proxy = new OmniseaERC721Proxy();
            collection = address(proxy);
            IOmniseaRemoteERC721(collection).initialize(_collectionParams);
            idToCollection[_collectionId] = collection;
            collectionToId[collection] = _collectionId;
        }

        uint nextIndex = _creditTill(_srcChainId, collection, toAddress, 0, tokenIds);
        if (nextIndex < tokenIds.length) {
            // not enough gas to complete transfers, store to be cleared in another tx
            bytes32 hashedPayload = keccak256(_payload);
            storedCredits[hashedPayload] = StoredCredit(_srcChainId, collection, toAddress, nextIndex, true);
            emit CreditStored(hashedPayload, _payload);
        }

        emit ReceiveFromChain(_srcChainId, _srcAddress, toAddress, tokenIds);
    }

    // Public function for anyone to clear and deliver the remaining batch sent tokenIds
    function clearCredits(bytes memory _payload) external virtual nonReentrant {
        bytes32 hashedPayload = keccak256(_payload);
        require(storedCredits[hashedPayload].creditsRemain);

        (,uint[] memory tokenIds) = abi.decode(_payload, (bytes, uint[]));

        uint nextIndex = _creditTill(storedCredits[hashedPayload].srcChainId, storedCredits[hashedPayload].collection, storedCredits[hashedPayload].toAddress, storedCredits[hashedPayload].index, tokenIds);
        require(nextIndex > storedCredits[hashedPayload].index);

        if (nextIndex == tokenIds.length) {
            // cleared the credits, delete the element
            delete storedCredits[hashedPayload];
            emit CreditCleared(hashedPayload);
        } else {
            // store the next index to mint
            storedCredits[hashedPayload] = StoredCredit(storedCredits[hashedPayload].srcChainId, storedCredits[hashedPayload].collection, storedCredits[hashedPayload].toAddress, nextIndex, true);
        }
    }

    // When a srcChain has the ability to transfer more chainIds in a single tx than the dst can do.
    // Needs the ability to iterate and stop if the minGasToTransferAndStore is not met
    function _creditTill(uint16 _srcChainId, address _collection, address _toAddress, uint _startIndex, uint[] memory _tokenIds) internal returns (uint256){
        uint i = _startIndex;
        while (i < _tokenIds.length) {
            if (gasleft() < minGasToTransferAndStore) break;

            _creditTo(_srcChainId, _collection, _toAddress, _tokenIds[i]);
            i++;
        }

        return i;
    }

    // limit on src the amount of tokens to batch send
    function setDstChainIdToLimits(uint16 _dstChainId, uint256 _dstChainIdToBatchLimit, uint256 _dstChainIdToTransferGas, uint256 _minGasToTransferAndStore) external onlyOwner {
        dstChainIdToBatchLimit[_dstChainId] = _dstChainIdToBatchLimit;
        dstChainIdToTransferGas[_dstChainId] = _dstChainIdToTransferGas;
        minGasToTransferAndStore = _minGasToTransferAndStore;
    }

    function _payONFTFee(uint _nativeFee) internal virtual returns (uint amount) {
        uint fee = fixedFee;
        amount = _nativeFee - fee;
        if (fee > 0) {
            (bool p,) = payable(revenueManager).call{value : (fee)}("");
            require(p);
        }
    }

    function _debitFrom(address _from, uint16, address _collection, bytes memory, uint _tokenId) internal virtual {
        IOmniseaRemoteERC721 collection = IOmniseaRemoteERC721(_collection);
        require(collection.ownerOf(_tokenId) == _from);
        collection.transferFrom(_from, address(this), _tokenId);
    }

    function _creditTo(uint16, address _collection, address _toAddress, uint _tokenId) internal virtual {
        IOmniseaRemoteERC721 collection = IOmniseaRemoteERC721(_collection);
        bool exists = collection.exists(_tokenId);

        require(!exists || (exists && collection.ownerOf(_tokenId) == address(this)));
        if (exists) {
            collection.transferFrom(address(this), _toAddress, _tokenId);
            return;
        }
        collection.mint(_toAddress, _tokenId);
    }

    function _toSingletonArray(uint element) internal pure returns (uint[] memory) {
        uint[] memory array = new uint[](1);
        array[0] = element;
        return array;
    }

    function setFactory(address _newFactory) external onlyOwner {
        _factory = IOmniseaDropsFactory(_newFactory);
    }
}

