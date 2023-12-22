// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {VestingWallet} from "./VestingWallet.sol";

/// @title Lumin Finance Vesting Wallet
/// @author bull.haus
/// @notice The Lumin Vesting Wallet is a wrapper around OpenZeppelin's Vesting Wallet, which adds a name identifier to
/// each wallet.
contract LuminVesting is VestingWallet {
    /// @notice Identifiable name of vesting wallet.
    string public name;

    /// @notice Create vesting wallet.
    /// @param walletName Identifiable name of vesting wallet.
    /// @param beneficiary Initial wallet owner.
    /// @param startTimestamp Timestamp of start of vesting.
    /// @param durationSeconds Duration of vesting in seconds.
    constructor(string memory walletName, address beneficiary, uint64 startTimestamp, uint64 durationSeconds)
        VestingWallet(beneficiary, startTimestamp, durationSeconds)
    {
        name = walletName;
    }
}

