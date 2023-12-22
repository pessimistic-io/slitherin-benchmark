// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IEtherealSpheresPool {
    error ProvidedRewardTooHigh();
    error InvalidArrayLength();
    error IncorrectOwner(uint256 tokenId);

    event RewardProvided(uint256 indexed reward);
    event Staked(address indexed account, uint256[] indexed tokenIds);
    event Withdrawn(address indexed account, uint256[] indexed tokenIds);
    event RewardPaid(address indexed account, uint256 indexed reward);

    /// @notice Provides total reward to the pool.
    /// @param reward_ Reward amount.
    function provideReward(uint256 reward_) external;

    /// @notice Stakes tokens for the caller.
    /// @param tokenIds_ Token ids to stake.
    function stake(uint256[] calldata tokenIds_) external;

    /// @notice Withdraws all staked tokens and transfers rewards to the caller. 
    function exit() external;

    /// @notice Withdraws tokens for the caller.
    /// @param tokenIds_ Token ids to withdraw.
    function withdraw(uint256[] memory tokenIds_) external;

    /// @notice Transfers earned rewards to the caller.
    function getReward() external;

    /// @notice Retrieves the token id staked by `account_`.
    /// @param account_ Account address.
    /// @param index_ Index value.
    /// @return Token id staked by `account_`.
    function getStakedTokenIdByAccountAt(address account_, uint256 index_) external view returns (uint256);

    /// @notice Returns boolean value indicating whether the account is in stakers list or not.
    /// @param account_ Account address.
    /// @return Boolean value indicating whether the account is stakers list or not.
    function isStaker(address account_) external view returns (bool);

    /// @notice Returns the length of the stakers list.
    /// @return The length of the stakers list.
    function stakersLength() external view returns (uint256);

    /// @notice Returns staker by index.
    /// @param index_ Index value.
    /// @return Staker by index.
    function stakerAt(uint256 index_) external view returns (address);

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
