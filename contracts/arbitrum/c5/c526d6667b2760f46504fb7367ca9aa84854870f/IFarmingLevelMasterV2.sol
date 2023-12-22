// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {IERC20} from "./IERC20.sol";

interface IFarmingLevelMasterV2 {
  function rewardToken() external view returns (IERC20);

  function lpToken(uint256 pid) external view returns (address);

  struct UserInfo {
    uint256 amount;
    int256 rewardDebt;
  }

  function userInfo(uint256 pid, address owner) external view returns (UserInfo memory userInfo);

  function pendingReward(uint256 pid, address owner) external view returns (uint256 pending);

  function deposit(uint256 pid, uint256 amount, address to) external;

  function withdraw(uint256 pid, uint256 amount, address to) external;

  function harvest(uint256 pid, address to) external;
}

