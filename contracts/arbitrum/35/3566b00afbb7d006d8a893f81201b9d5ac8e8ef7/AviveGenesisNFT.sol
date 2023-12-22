// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC721.sol";
import "./ERC721Burnable.sol";
import "./Ownable.sol";
import "./Strings.sol";

abstract contract AviveGenesisNFT is ERC721, ERC721Burnable, Ownable {
    using Strings for uint256;
    string private _baseuri;
    uint256 public totalSupply = 0;
    bool public TradingOpen = false;

    constructor(string memory baseuri_) ERC721('Avive Genesis NFT', 'Genesis') {
        _baseuri = baseuri_;
    }

    function setTradingOpen(bool open) external onlyOwner {
        TradingOpen = open;
    }

    function setBaseURI(string memory uri) external onlyOwner {
        require(bytes(uri).length > 0, 'wrong base uri');
        _baseuri = uri;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireMinted(tokenId);
        return string(abi.encodePacked(_baseuri, tokenId.toString(), '/'));
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        if (from == address(0)) {
            totalSupply += batchSize;
        } else if (to != address(0)) {
            require(TradingOpen, 'trading not open');
        }
        if (to == address(0)) {
            totalSupply -= batchSize;
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

