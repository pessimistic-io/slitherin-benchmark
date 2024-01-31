// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721Enumerable.sol";

interface INFTCore is IERC721Enumerable {
    function mint(address to) external returns (uint256 tokenId);
}

