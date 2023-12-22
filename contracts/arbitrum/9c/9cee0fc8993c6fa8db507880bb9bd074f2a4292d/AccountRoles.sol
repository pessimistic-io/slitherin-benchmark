// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

enum AccountRole {
    // This role is an invalid role and is not used.
    // Its purpose is to add padding to the starting role value of 1,
    // so that the value of 0 is an invalid role.
    None,
    // The owner holds the account NFT and has all permissions.
    Owner,
    Trader,
    Withdraw,
    // The Deposit role is a permissionless role.
    // Anyone can deposit into any account, therefore it does not need to be granted.
    Deposit,
    // The Open role is a permissionless role.
    // It is used for opening an account, alongside the initial account deposit.
    Open
}

