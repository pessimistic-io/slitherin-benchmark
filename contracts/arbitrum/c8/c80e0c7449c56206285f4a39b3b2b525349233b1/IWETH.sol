// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETH {
    function transfer(address to, uint256 value) external returns (bool);
    function deposit() external payable;
    function withdraw(uint256) external;
}

