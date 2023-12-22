// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

interface IStakingRewards {
    // Structs

    /// stakingToken : Address of the token that will be staked
    /// rewardToken : Address of the token that will be given as reward
    /// rewardRate : Rate at which the rewards will be calculated,
    ///             reward rate will be multiplied by 100 for decimal precision,
    ///             for e.g. 6000 means 60%/year, 1000 means 10%/year
    /// start : Start time of the staking pool
    /// end : Ending time for the staking pool
    struct Pool {
        address stakingToken;
        address rewardToken;
        uint256 rewardRate;
        uint256 totalAmount;
        uint256 start;
        uint256 end;
    }

    ///balance : Staked balance of a user
    ///lastRewarded : The time at which a user was last rewarded
    ///rewards : Amount of rewards accrued by a user(Note - This is not a track of
    /// real time rewards,this is a track of rewards till the last time user interacted with
    /// the last rewarded variable)
    struct UserInfo {
        uint256 balance;
        uint256 lastRewarded;
        uint256 rewards;
    }

    // Events

    event Staked(address indexed user, uint256 amount, uint256 poolId);
    event Withdrawn(address indexed user, uint256 amount, uint256 poolId);
    event RewardPaid(address indexed user, uint256 poolId, uint256 reward);
    event RewardsDeposited(address depositor, uint256 poolId, uint256 amount);
    event RewardsWithdrawn(uint256 amount, uint256 poolId);

    // Functions

    function createPool(
        address stakingToken,
        address rewardToken,
        uint256 rewardRate,
        uint256 start,
        uint256 end
    ) external;

    function stake(uint256 amount, uint256 poolId) external;

    function stakeFor(address user, uint256 amount, uint256 poolId) external;

    function unstake(uint256 poolId) external;

    function depositRewards(uint256 poolId, uint256 amount) external;

    function withdrawRewards(
        uint256 poolId,
        uint256 amount,
        address receiver
    ) external;

    function setJobState(uint256 poolId, bool pause) external;

    function claimPendingRewards(uint256 poolId) external;

    function getRewardsForAPool(
        address account,
        uint256 poolId
    ) external view returns (uint256);

    function getPools()
        external
        view
        returns (Pool[] memory pools, string[] memory symbols);

    function getPool(uint256 poolId) external view returns (Pool memory pool);
}

