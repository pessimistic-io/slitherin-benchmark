// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IAccountsEvents {
    event Deposit(address indexed party, uint256 amount);
    event Withdraw(address indexed party, uint256 amount);
    event Allocate(address indexed party, uint256 amount);
    event Deallocate(address indexed party, uint256 amount);
    event AddFreeMarginIsolated(address indexed party, uint256 amount, uint256 indexed positionId);
    event AddFreeMarginCross(address indexed party, uint256 amount);
    event RemoveFreeMarginCross(address indexed party, uint256 amount);
}

