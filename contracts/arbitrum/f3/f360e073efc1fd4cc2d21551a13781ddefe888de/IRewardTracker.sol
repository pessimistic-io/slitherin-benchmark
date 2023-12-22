// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @notice Froked from https://github.com/gmx-io/gmx-contracts/blob/master/contracts/staking/interfaces/IRewardTracker.sol
interface IRewardTracker {
  function updateRewards() external;
  function stake(address _account, uint256 _amount) external;
  function unstake(address _account, uint256 _amount) external;
  function claim() external returns (uint256);
  function rewardToken() external view returns (address);
}

