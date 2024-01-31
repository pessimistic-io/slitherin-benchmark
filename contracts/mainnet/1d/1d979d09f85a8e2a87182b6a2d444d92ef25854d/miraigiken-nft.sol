//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.2;

import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./console.sol";

contract Dev is ERC721, ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    uint256 private _index;

    constructor() ERC721("Dev", "CLTD") {}

    function tokenURI(uint256 tokenId)
        public 
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _burn(uint256 tokenId)
        internal 
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    // Mint a new one NFT
    function mintNft(address player, string memory uri)
        external
        returns (uint256)
    {
        require(player != address(0), "Invalid address");

        _tokenIdCounter.increment();
        uint256 newItemId = _tokenIdCounter.current();

        _safeMint(player, newItemId);
        _setTokenURI(newItemId, uri);

        emit Transfer(address(0), player, newItemId);
        return newItemId;
    }

    // Update NFT token URI
    function updateNftTokenUri(uint256 tokenId, string memory uri)
        external
        returns (uint256)
    {
        require(ownerOf(tokenId) == msg.sender, "Invalid token owner");
        _setTokenURI(tokenId, uri);

        emit Transfer(address(0), msg.sender, tokenId);
        return tokenId;
    }
}
