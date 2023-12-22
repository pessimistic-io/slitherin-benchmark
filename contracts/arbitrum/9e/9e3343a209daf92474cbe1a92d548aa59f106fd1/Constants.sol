/**
 * Utility constants for the vault
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

abstract contract VaultConstants {
    /**
     * Constant memory location for where user's withdraw shares are stored in memory
     */
    uint256 internal constant WITHDRAW_SHARES_MEM_LOCATION =
        0x00000000000000000000000000000000000000000000000000000000000000000080;
    /**
     * Constant memory location for where user's deposit amount is stored in memory
     */
    uint256 internal constant DEPOSIT_AMT_MEM_LOCATION =
        0x00000000000000000000000000000000000000000000000000000000000000000080;
}

