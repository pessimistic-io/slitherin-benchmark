// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILVLStaking {
  function currentEpoch() external view returns (uint256);
  function stakedAmounts(address _user) external view returns (uint256);
  function stake(address _to, uint256 _amount) external;
  function unstake(address _to, uint256 _amount) external;
  function claimRewards(uint256 _epoch, address _to) external;
  function pendingRewards(uint256 _epoch, address _user) external view returns (uint256);
}

