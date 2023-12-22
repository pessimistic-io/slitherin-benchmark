/**
 * Utility constants for the vault
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract VaultConstants {
    /**
     * Constant memory location for where user's withdraw shares are stored in memory
     */
    uint256 internal constant WITHDRAW_SHARES_MEM_LOCATION = 0x320;
    /**
     * Constant memory location for where user's deposit amount is stored in memory
     */
    uint256 internal constant DEPOSIT_AMT_MEM_LOCATION = 0x3e4;

    /**
     * Constant "delta" variable that we require when sending gas in individual users' operations.
     *
     * For instance, if our approximation for a deposit gas on a vault is 500K WEI, and the delta is 2, then
     * we require the msg.value (the "extra" prepaid gas) to be atleast 500K WEI * 2 = 1M WEI.
     */
    uint256 internal constant GAS_FEE_APPROXIMATION_DELTA = 2;
}

