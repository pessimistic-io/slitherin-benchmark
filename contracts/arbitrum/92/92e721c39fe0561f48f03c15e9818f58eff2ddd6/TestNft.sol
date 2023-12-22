// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./ERC721.sol";

contract TestNft is ERC721 {
    constructor() ERC721("MyNFT", "MNFT") public {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
