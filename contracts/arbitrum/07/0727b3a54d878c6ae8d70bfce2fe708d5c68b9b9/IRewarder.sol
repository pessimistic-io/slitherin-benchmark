// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRewarder {
    function pendingReward(address user) external view returns (uint256);

    function getPendingUSDCRewards() external view returns (uint256);
}

