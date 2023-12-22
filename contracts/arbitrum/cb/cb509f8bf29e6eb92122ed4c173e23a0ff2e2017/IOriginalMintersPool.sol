// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IOriginalMintersPool {
    error ProvidedRewardTooHigh();

    event RewardProvided(uint256 indexed reward);
    event RewardPaid(address indexed account, uint256 indexed reward);

    /// @notice Updates stake for original minter.
    /// @param account_ Account address.
    /// @param summand_ Summand for existing stake.
    function updateStakeFor(address account_, uint256 summand_) external;

    /// @notice Provides total reward to the pool.
    /// @param reward_ Reward amount.
    function provideReward(uint256 reward_) external;

    /// @notice Transfers earned rewards to the caller.
    function getReward() external;

    /// @notice Retrieves the time a reward was applicable.
    /// @return Last time reward was applicable.
    function lastTimeRewardApplicable() external view returns (uint256);

    /// @notice Retrieves the reward per token value.
    /// @return Reward per token value.
    function rewardPerToken() external view returns (uint256);

    /// @notice Retrieves the earned reward by `account_`.
    /// @param account_ Account address.
    /// @return Earned reward by `account_`.
    function earned(address account_) external view returns (uint256);
}
