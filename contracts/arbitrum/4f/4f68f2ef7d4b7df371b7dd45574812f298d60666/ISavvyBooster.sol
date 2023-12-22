// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ISavvyPositionManager.sol";

/// @title  ISavvyBooster
/// @author Savvy DeFi
interface ISavvyBooster {
    /// @dev The struct to show each pool Info.
    /// @dev Pool Info represents each emission supply pool.
    struct PoolInfo {
        /// @dev The amount of svy emissions remaining for this pool.
        uint256 remainingEmissions;
        /// @dev [emission supply amount] / [emission supplying duration].
        uint256 emissionRatio;
        /// @dev Duration timestamp between (this supplied time) - (last supplied time).
        uint256 duration;
        /// @dev Supplied timestamp.
        uint256 startTime;
        /// @dev total debt in Savvy protocol.
        uint256 totalDebtBalance;
        /// @dev total veSVY in Savvy protocol.
        uint256 totalVeSvyBalance;
    }

    /// @dev The struct to represent user info.
    struct UserInfo {
        /// @dev Amount that you can claim.
        /// @dev It's real * 1e18.
        uint256 pendingRewards;
        /// @dev The timestamp that a msterSavvy updated lastly.
        uint256 lastUpdateTime;
        /// @dev The last pool when the user info was updated.
        uint256 lastUpdatePool;
        /// @dev User's last debt bablance.
        uint256 debtBalance;
        /// @dev User's last veSVY balance.
        uint256 veSvyBalance;
    }

    /// @notice Set savvyPositionManager address.
    /// @dev Only owner can call this function.
    /// @param savvyPositionManagers The address list of new savvyPositionManager.
    function addSavvyPositionManagers(
        ISavvyPositionManager[] calldata savvyPositionManagers
    ) external;

    /// @notice Add new pool to deposit svy emissions.
    /// @dev Only owner can call this function.
    /// @param amount Amount of svy emissions.
    /// @param duration Duration of emission deposit.
    function addPool(uint256 amount, uint256 duration) external;

    /// @notice Remove a future queued pool and withdraw svy emissions.
    /// @dev Only owner can call this function.
    /// @dev This function can be called only when the pool is not started yet.
    /// @param period The period of pool to remove.
    function removePool(uint256 period) external;

    /// @notice User claims boosted SVY rewards.
    /// @return Amount of rewards claimed.
    function claimSvyRewards() external returns (uint256);

    /// @notice Update pending rewards when user's debt balance changes.
    /// @dev Only savvyPositionManager calls this function when user's debt balance changes.
    /// @param user The address of user that wants to get rewards.
    /// @param userDebtSavvy User's debt balance in USD of savvyPositionManager.
    /// @param totalDebtSavvy Total debt balance in USD of savvyPositionManager.
    function updatePendingRewardsWithDebt(
        address user,
        uint256 userDebtSavvy,
        uint256 totalDebtSavvy
    ) external;

    /// @notice Update pending rewards when user's veSvy balance changes.
    /// @dev VeSvy contract call this function when user's veSvy balance is updated.
    /// @param user The address of a user.
    /// @param userVeSvyBalance User's veSVY balance.
    /// @param totalVeSvyBalance Total veSVY balance.
    function updatePendingRewardsWithVeSvy(
        address user,
        uint256 userVeSvyBalance,
        uint256 totalVeSvyBalance
    ) external;

    /// @notice Get the claimable rewards amount accrued for user.
    /// @param user The address of a user.
    /// @return pending rewards amount of a user.
    function getClaimableRewards(address user) external view returns (uint256);

    /// @notice Get current svy earning rate of a user.
    /// @param user The address of a user.
    /// @return amount of current svy earning reate.
    function getSvyEarnRate(address user) external view returns (uint256);

    /// @notice withdraw svyToken to owner.
    function withdraw() external;

    /// @notice deposit svyToken into new pool.
    event Deposit(uint256 amount, uint256 poolId);

    /// @notice withdraw svyToken to owner.
    event Withdraw(uint256 amount);

    /// @notice claim svyToken rewards.
    /// @dev If pendingAmount is greater than 0, this is a warning concern.
    event Claim(
        address indexed user,
        uint256 rewardAmount,
        uint256 pendingAmount
    );
}

