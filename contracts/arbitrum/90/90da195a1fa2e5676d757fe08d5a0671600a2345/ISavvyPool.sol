// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface ISavvyPool {
    /// @notice Get user’s deposit in a pool.
    /// @param user The address of a user.
    /// @param poolAddr The address of beefy a pool.
    /// @return Returns deposited amount in a pool.
    function getPoolDeposited(
        address user,
        address poolAddr
    ) external view returns (uint256);

    /// @notice Get total deposited by Savvy in pool vs total capped amount for pool
    /// @param poolAddr The address of beefy a pool.
    /// @param savvyPositionManager The address of SavvyPositionManager.
    /// @return total deposited by Savvy in pool, total capped amount for pool
    function getPoolUtilization(
        address poolAddr,
        address savvyPositionManager
    ) external view returns (uint256, uint256);
}

