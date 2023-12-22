// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Address.sol";

contract KnightNFT is ERC721, Ownable {
    constructor() ERC721("KnightNFT", "KNT") {}

    function mint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
    }
}

