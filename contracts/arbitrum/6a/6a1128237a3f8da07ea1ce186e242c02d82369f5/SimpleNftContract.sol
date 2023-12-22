// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Counters.sol";
import "./Ownable.sol";
import "./ERC721.sol";

contract SimpleNftContract is ERC721, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    string private _tokenUri;

    constructor(
        string[3] memory strings
    ) ERC721(strings[0], strings[1])
    {
        _tokenUri = strings[2];
    }

    function tokenURI(uint256 tokenId)
    public
    view
    override
    returns (string memory)
    {
        _requireMinted(tokenId);
        return _tokenUri;
    }

    function safeMint(address to)
    public
    onlyOwner
    {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    function setTokenUri(string memory tokenUri_)
    public
    onlyOwner
    {
        _tokenUri = tokenUri_;
    }

    function safeMints(address to, uint256 amount)
    public
    onlyOwner
    {
        for (uint256 i = 0; i < amount; i++) {
            safeMint(to);
        }
    }
}

