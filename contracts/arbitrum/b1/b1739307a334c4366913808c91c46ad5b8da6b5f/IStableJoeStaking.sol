// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.8;

interface IStableJoeStaking {
  function deposit(uint256 _amount) external;

  function getUserInfo(address _user, address _rewardToken) external view returns (uint256, uint256);

  function joe() external view returns (address);

  function pendingReward(address _user, address _token) external view returns (uint256);

  function withdraw(uint256 _amount) external;
}

