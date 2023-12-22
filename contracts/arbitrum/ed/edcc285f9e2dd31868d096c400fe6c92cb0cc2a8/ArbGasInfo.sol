// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Provides insight into the cost of using the chain.
/// @notice These methods have been adjusted to account for Nitro's heavy use of calldata compression.
/// Of note to end-users, we no longer make a distinction between non-zero and zero-valued calldata bytes.
/// Precompiled contract that exists in every Arbitrum chain at 0x000000000000000000000000000000000000006c.
interface ArbGasInfo {
    /// @notice Get L1 gas fees paid by the current transaction
    function getCurrentTxL1GasFees() external view returns (uint256);
}

