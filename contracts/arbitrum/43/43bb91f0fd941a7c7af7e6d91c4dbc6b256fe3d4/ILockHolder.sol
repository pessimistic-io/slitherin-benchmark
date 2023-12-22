// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.13;

interface ILockHolder {
    /// @notice Transfers all the rewards earned by the lock to the partner.
    /// @param tokens_ Reward token addresses.
    function sendRewards(address[][] calldata tokens_) external;
}
