// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ITreasurySharePool {
    event Stake(address indexed account, uint256 round, uint256 amount);
    event Unstake(address indexed account, uint256 round, uint256 amount);
    event Claim(address indexed account, uint256 amount);
    event RoundEnd(
        uint256 round,
        uint256 roundStaked,
        uint256 roundReward,
        uint256 rewardIndex,
        uint256 totalStaked,
        uint256 totalReward,
        uint256 totalRewardUsed
    );
    event UserUpdated(address indexed account, uint256 newDebt, uint256 newIndex, uint256 unclaimStaked);

    /**
     * @notice Stake the token to the pool
     * @param amount The amount of token to stake
     */
    function stake(uint256 amount) external;
    /**
     * @notice Unstake the token from the pool
     * @param amount The amount of token to unstake
     * @param force Force unstake the token, even the token is preUnlocked.
     */
    function unstake(uint256 amount, bool force) external;

    /**
     * @notice Claim the unclaimed rewardfrom the pool
     */
    function claim() external;

    /**
     * @notice Get the stake information of an account
     * @param account The account to get the stake information
     * @return staking The amount of staking in the pool
     * @return inQueue The amount of stake in the current round
     * @return rewards The amount of reward in the pool
     * @return pendingReward The amount of reward in the previous round.
     */
    function getStakeInfo(address account)
        external
        view
        returns (uint256 staking, uint256 inQueue, uint256 rewards, uint256 pendingReward);

    /**
     * @notice Get the round information
     * @param round The round number, the max uint256 is the current round.
     * @return staked The total amount of stake in round `round`.
     * @return reward The amount of reward in the round
     */
    function getRoundInfo(uint256 round) external view returns (uint256 staked, uint256 reward);
    /**
     * @dev Get the current round  number
     */
    function currentRound() external view returns (uint256);

    /**
     * @notice Get the pool information
     * @return currRound The current round number
     * @return staked The total amount of stake in the pool
     * @return rewardBalance The amount of reward in the pool
     * @return accruedReward The accrued reward amount.
     * @return accruedUsedReward The accrued distribution out reward.
     * @return nextRoundStartAt Timestamp for the start of the next round.
     */
    function getPoolInfo()
        external
        view
        returns (
            uint256 currRound,
            uint256 staked,
            uint256 rewardBalance,
            uint256 accruedReward,
            uint256 accruedUsedReward,
            uint256 nextRoundStartAt
        );
}

