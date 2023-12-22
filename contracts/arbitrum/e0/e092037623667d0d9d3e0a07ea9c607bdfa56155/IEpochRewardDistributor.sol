// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface IEpochRewardDistributor {
    function distribute(address rewardToken, uint256 amount) external returns (uint256);
}

