// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC721Enumerable.sol";
import "./ERC721.sol";

contract TestERC721 is ERC721Enumerable {
    uint256 public tokenId;

    constructor() ERC721("TestToken ERC721", "TTERC721") {
        tokenId = 1;
    }

    function mint(address receiver) public {
        _safeMint(receiver, tokenId);
        tokenId++;
    }
}

