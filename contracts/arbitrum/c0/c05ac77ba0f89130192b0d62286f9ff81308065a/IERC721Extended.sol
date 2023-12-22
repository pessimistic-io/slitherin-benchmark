// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721.sol";

interface IERC721Extended is IERC721 {
    function tokenURI(uint256 tokenId) external returns (string memory);
}

