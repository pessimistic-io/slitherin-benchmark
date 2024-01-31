// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC721.sol";

interface IERC721Mintable is IERC721 {
    function safeMint(address to) external returns (uint256);
}

