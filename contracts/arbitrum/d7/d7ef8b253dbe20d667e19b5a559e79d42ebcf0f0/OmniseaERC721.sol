// SPDX-License-Identifier: MIT
// omnisea-contracts v0.1

pragma solidity ^0.8.7;

import "./IOmniseaONFT721.sol";
import "./IOmniseaRemoteERC721.sol";
import "./ERC721.sol";
import "./IOmniseaUniversalONFT721.sol";
import "./Strings.sol";
import {BasicCollectionParams} from "./ERC721Structs.sol";

contract OmniseaERC721 is IOmniseaRemoteERC721, IOmniseaONFT721, ERC721 {
    using Strings for uint256;

    IOmniseaUniversalONFT721 public universalONFT;
    address public owner;
    string public collectionURI;
    string public tokensURI;
    uint24 public maxSupply;
    uint256 public totalSupply;
    bool private isInitialized;

    function initialize(BasicCollectionParams memory params) external {
        require(!isInitialized);
        _init(params.name, params.symbol);
        isInitialized = true;
        universalONFT = IOmniseaUniversalONFT721(msg.sender);
        owner = params.owner;
        collectionURI = params.uri;
        tokensURI = params.tokensURI;
        maxSupply = params.maxSupply;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://";
    }

    function contractURI() public view returns (string memory) {
        return string(abi.encodePacked(_baseURI(), collectionURI));
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (maxSupply == 0) {
            return contractURI();
        }

        return string(abi.encodePacked(_baseURI(), tokensURI, "/", tokenId.toString(), ".json"));
    }

    function mint(address _owner, uint256 tokenId) override external {
        require(msg.sender == address(universalONFT));
        _safeMint(_owner, tokenId);
        unchecked {
            totalSupply++;
        }
    }

    function exists(uint256 tokenId) public view virtual override returns (bool) {
        return _exists(tokenId);
    }

    function sendFrom(address _from, uint16 _dstChainId, bytes calldata _toAddress, uint _tokenId, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external override payable {
        require(_from == msg.sender);
        universalONFT.sendFrom{value: msg.value}(_from, _dstChainId, _toAddress, _tokenId, _refundAddress, _zroPaymentAddress, _adapterParams, _getBasicCollectionParams());
    }

    function estimateSendFee(uint16 _dstChainId, bytes calldata _toAddress, uint _tokenId, bool _useZro, bytes calldata _adapterParams) external override view returns (uint nativeFee, uint zroFee) {
        return universalONFT.estimateSendFee(_dstChainId, _toAddress, _tokenId, _useZro, _adapterParams, _getBasicCollectionParams());
    }

    function sendBatchFrom(address _from, uint16 _dstChainId, bytes calldata _toAddress, uint[] calldata _tokenIds, address payable _refundAddress, address _zroPaymentAddress, bytes calldata _adapterParams) external override payable {
        require(_from == msg.sender);
        universalONFT.sendBatchFrom{value: msg.value}(_from, _dstChainId, _toAddress, _tokenIds, _refundAddress, _zroPaymentAddress, _adapterParams, _getBasicCollectionParams());
    }

    function estimateSendBatchFee(uint16 _dstChainId, bytes calldata _toAddress, uint[] calldata _tokenIds, bool _useZro, bytes calldata _adapterParams) external override view returns (uint nativeFee, uint zroFee) {
        return universalONFT.estimateSendBatchFee(_dstChainId, _toAddress, _tokenIds, _useZro, _adapterParams, _getBasicCollectionParams());
    }

    function _getBasicCollectionParams() internal view returns (BasicCollectionParams memory) {
        return BasicCollectionParams(name(), symbol(), collectionURI, tokensURI, maxSupply, owner);
    }
}

