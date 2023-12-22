// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";

import "./IZKBridgeErc721.sol";

contract ZKBridgeErc721 is IZKBridgeErc721, ERC721 {
    address public bridge;

    mapping(uint256 => string) private tokenURIs;

    modifier onlyBridge() {
        require(msg.sender == bridge, "caller is not the bridge");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        bridge = msg.sender;
    }

    function zkBridgeMint(
        address _to,
        uint256 _tokenId,
        string memory tokenURI_
    ) external override onlyBridge {
        _mint(_to, _tokenId);
        _setTokenURI(_tokenId, tokenURI_);
    }

    function zkBridgeBurn(uint256 _tokenId) external override onlyBridge {
        require(_exists(_tokenId), "Burn of nonexistent token");
        _burn(_tokenId);
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override(ERC721, IZKBridgeErc721) returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");
        return tokenURIs[_tokenId];
    }

    function _setTokenURI(uint256 _tokenId, string memory tokenURI_) internal {
        require(_exists(_tokenId), "URI set of nonexistent token");
        tokenURIs[_tokenId] = tokenURI_;
    }
}

