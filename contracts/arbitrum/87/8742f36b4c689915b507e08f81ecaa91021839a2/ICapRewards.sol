// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface ICapRewards {
  function collectReward() external;

  function cumulativeRewardPerTokenStored() external view returns (uint256);

  function currency() external view returns (address);

  function getClaimableReward() external view returns (uint256);

  function notifyRewardReceived(uint256 amount) external;

  function owner() external view returns (address);

  function pendingReward() external view returns (uint256);

  function pool() external view returns (address);

  function router() external view returns (address);

  function setOwner(address newOwner) external;

  function setRouter(address _router) external;

  function trading() external view returns (address);

  function treasury() external view returns (address);

  function updateRewards(address account) external;
}

