// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETHWithdrawAdapter {
    function withdraw(address recipient, uint256 amount, bytes memory data) external;
}

