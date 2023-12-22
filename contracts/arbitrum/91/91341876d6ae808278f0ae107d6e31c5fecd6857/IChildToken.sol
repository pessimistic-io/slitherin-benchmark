// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IChildToken {
    function deposit(address user, bytes calldata depositData) external;
}

