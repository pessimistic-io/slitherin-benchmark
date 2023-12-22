// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

// Custom ERC20 interface for 2 methods.

interface cIERC20 {
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}


