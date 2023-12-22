// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

interface IAgent {
    event AccountCreated(address indexed trader, address indexed account);
    event VaultDeposited(
        uint256 nonce,
        address indexed account,
        address indexed baseToken,
        address indexed token,
        uint256 amount
    );
    event VaultWithdraw(
        uint256 nonce,
        address indexed account,
        address indexed baseToken,
        address indexed token,
        uint256 amount
    );
    event Deposited(uint256 nonce, address indexed account, address indexed token, uint256 amount);
    event Withdraw(uint256 nonce, address indexed account, address indexed token, uint256 amount);
    event FeeCharged(uint256 nonce, address indexed account, address indexed token, uint256 amount);
    event RewardClaimed(uint256 nonce, address indexed account, uint256 amount);
    event TxFeeWithdraw(uint256 amount);
}

