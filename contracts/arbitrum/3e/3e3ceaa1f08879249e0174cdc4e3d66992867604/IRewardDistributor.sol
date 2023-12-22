// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8;

interface IRewardDistributor {
  event Distribute(uint256 amount);
  event TokensPerIntervalChange(uint256 amount);

  function rewardToken() external view returns (address);

  function tokensPerInterval() external view returns (uint256);

  function pendingRewards() external view returns (uint256);

  function distribute() external returns (uint256);
}

