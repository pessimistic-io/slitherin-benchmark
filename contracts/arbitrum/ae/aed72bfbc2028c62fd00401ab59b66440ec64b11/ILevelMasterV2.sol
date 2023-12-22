// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


interface ILevelMasterV2 {
  function pendingReward(
    uint256 _pid,
    address _user
  ) external view returns (uint256 pending);
  function userInfo(
    uint256 _pid,
    address _user
  ) external view returns (uint256, int256);
  function deposit(uint256 pid, uint256 amount, address to) external;
  function withdraw(uint256 pid, uint256 amount, address to) external;
  function harvest(uint256 pid, address to) external;
  function addLiquidity(
    uint256 pid,
    address assetToken,
    uint256 assetAmount,
    uint256 minLpAmount,
    address to
  ) external;
  function removeLiquidity(
    uint256 pid,
    uint256 lpAmount,
    address toToken,
    uint256 minOut,
    address to
  ) external;
}

