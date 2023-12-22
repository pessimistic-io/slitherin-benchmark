// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "./ERC721.sol";

import "./IZKBridgeSBT.sol";

contract ZKBridgeSBT is IZKBridgeSBT, ERC721 {
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
    }

    function zkBridgeMint(
        address _to,
        uint256 _tokenId,
        string memory tokenURI_
    ) external override onlyBridge {
        _mint(_to, _tokenId);
        _setTokenURI(_tokenId, tokenURI_);
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override returns (string memory) {
        require(_exists(_tokenId), "URI query for nonexistent token");
        return tokenURIs[_tokenId];
    }

    function _setTokenURI(uint256 _tokenId, string memory tokenURI_) internal {
        require(_exists(_tokenId), "URI set of nonexistent token");
        tokenURIs[_tokenId] = tokenURI_;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
        require(from == address(0), "SoulBound");
    }

    function initBridge(address _bridge) external {
        require(bridge == address(0), "initialized");
        bridge = _bridge;
    }


}


