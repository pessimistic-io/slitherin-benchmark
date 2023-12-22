// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGmxRewardTracker {
  function rewardToken() external view returns (address);

  function claimable(address _account) external view returns (uint256);

  function claim(address _receiver) external returns (uint256);

  function stakedAmounts(address _account) external returns (uint256);
}

