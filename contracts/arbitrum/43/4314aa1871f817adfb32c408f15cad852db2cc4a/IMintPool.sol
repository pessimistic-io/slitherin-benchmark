// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMintPool {
    function mint(address to, uint256 amount) external;
}

