// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IJonesGlpRewardsSplitter {
    /**
     * @notice Split the rewards comming from GMX
     * @param _amount of rewards to be splited
     * @param _leverage current strategy leverage
     * @param _utilization current stable pool utilization
     * @return Rewards splited in three, GLP rewards, Stable Rewards & Jones Rewards
     */
    function splitRewards(uint256 _amount, uint256 _leverage, uint256 _utilization)
        external
        returns (uint256, uint256, uint256);

    error TotalPercentageExceedsMax();
}

