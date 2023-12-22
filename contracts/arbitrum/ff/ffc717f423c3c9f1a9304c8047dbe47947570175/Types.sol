// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * Types for Perpie
 */

struct Transaction {
    address to;
    bytes callData;
    uint256 value;
}

