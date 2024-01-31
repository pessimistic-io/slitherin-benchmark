// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721.sol";

contract MockERC721Reservoir is ERC721 {
    constructor() ERC721("Mock", "MOCK") {}

    function mint(uint256 tokenId) external {
        _mint(msg.sender, tokenId);
    }
}

