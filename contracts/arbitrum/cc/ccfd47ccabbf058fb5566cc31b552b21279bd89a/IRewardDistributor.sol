// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.4;

interface IRewardDistributor {
    function rewardToken() external view returns (address);

    function tokensPerInterval() external view returns (uint256);

    function pendingRewards() external view returns (uint256);

    function distribute() external returns (uint256);
}

