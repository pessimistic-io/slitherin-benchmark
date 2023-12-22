// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

enum LiquidityPoolRole {
    // This role is an invalid role and is not used.
    // Its purpose is to add padding to the starting role value of 1,
    // so that the value of 0 is an invalid role.
    None,
    // The owner holds the account NFT and has all permissions.
    Owner,
    // The Deposit role is a permissionless role.
    // Anyone can deposit into any LP, therefore it does not need to be granted.
    Deposit
}

