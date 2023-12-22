// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ILeverageStrategyReward {
    function claimRewards() external;

    function claimRewards(address token) external;
}

