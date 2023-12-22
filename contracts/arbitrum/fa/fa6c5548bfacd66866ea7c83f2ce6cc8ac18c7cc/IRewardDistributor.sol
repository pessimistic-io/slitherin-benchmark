// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IRewardDistributor {
  function rewardToken() external view returns (address);
  function yieldTokensPerInterval(address yield) external view returns (uint256);
  function yieldLastDistributionTime(address yield) external view returns (uint256);
  function pendingRewards(address yield) external view returns (uint256);
  function distribute() external returns (uint256);
}

