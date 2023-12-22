// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ONFT721.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract UniversalONFT721 is ONFT721 {
    using SafeMath for uint256;
    uint public nextMintId;
    uint public maxMintId;
    uint public fee;
    string baseURI = "https://nfts.ZeroSquare.xyz/";
    uint256 feeBridge = 200;

    /// @notice Constructor for the UniversalONFT
    /// @param _name the name of the token
    /// @param _symbol the token symbol
    /// @param _layerZeroEndpoint handles message transmission across chains
    /// @param _startMintId the starting mint number on this chain
    /// @param _endMintId the max number of mints on this chain
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _minGasToTransfer,
        address _layerZeroEndpoint,
        uint _startMintId,
        uint _endMintId
    ) ONFT721(_name, _symbol, _minGasToTransfer, _layerZeroEndpoint) {
        nextMintId = _startMintId;
        maxMintId = _endMintId;
        fee = 0.00031 ether; // half a buck
    }

    /// @notice Mint your ONFT
    function mint() external payable {
        require(nextMintId <= maxMintId, "ZeroSquare: max mint limit reached");
        require(msg.value >= fee, "Not enough ETH sent: check fee.");
        uint newId = nextMintId;
        nextMintId++;

        _safeMint(msg.sender, newId);
    }

    // set fee for bridge
    function setFeeBridge(uint256 _fee) external onlyOwner {
        feeBridge = _fee;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _baseUri) public onlyOwner {
        baseURI = _baseUri;
    }

    function crossChain(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint _tokenId,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) public payable {
        uint256 amountValue = msg.value.sub(
            msg.value.mul(feeBridge).div(1000)
        );
        _send(
            _from,
            _dstChainId,
            _toAddress,
            _toSingletonArray(_tokenId),
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams,
            amountValue
        );
    }

    function _send(
        address _from,
        uint16 _dstChainId,
        bytes memory _toAddress,
        uint[] memory _tokenIds,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        uint _amountValue
    ) internal virtual {
        // allow 1 by default
        require(_tokenIds.length > 0, "tokenIds[] is empty");
        require(
            _tokenIds.length == 1 ||
                _tokenIds.length <= dstChainIdToBatchLimit[_dstChainId],
            "batch size exceeds dst batch limit"
        );

        for (uint i = 0; i < _tokenIds.length; i++) {
            _debitFrom(_from, _dstChainId, _toAddress, _tokenIds[i]);
        }

        bytes memory payload = abi.encode(_toAddress, _tokenIds);

        _checkGasLimit(
            _dstChainId,
            FUNCTION_TYPE_SEND,
            _adapterParams,
            dstChainIdToTransferGas[_dstChainId] * _tokenIds.length
        );
        _lzSend(
            _dstChainId,
            payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams,
            _amountValue
        );
        emit SendToChain(_dstChainId, _from, _toAddress, _tokenIds);
    }

    function withdrawETH() external onlyOwner returns (bool) {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        return success;
    }

    function setFee(uint _fee) external onlyOwner {
        fee = _fee;
    }
}

