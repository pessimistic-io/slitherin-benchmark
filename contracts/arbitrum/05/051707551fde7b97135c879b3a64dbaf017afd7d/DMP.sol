// SPDX-License-Identifier: MIT

// https://twitter.com/dealmpoker1
// https://discord.gg/hdgaZUqBSs
// https://t.me/+OZenwkiHEpliOGY0
// https://www.facebook.com/dealmpoker

pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract DMP is ERC721, ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    mapping(address => bool) public controller;
    mapping(address => string) public nameSurname;

    constructor() ERC721("DMP", "DMP") {}

    function safeMint(address to, string memory nameAndSurname) public {
        require(controller[msg.sender] == true, "Caller is not controller");
        require(balanceOf(to) == 0, "Can't hold more than 1");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        nameSurname[to] = nameAndSurname;
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function setController(address _addr, bool _value) public onlyOwner {
        controller[_addr] = _value;
    }
}

