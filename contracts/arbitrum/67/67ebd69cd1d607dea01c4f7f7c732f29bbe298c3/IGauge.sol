// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

interface IGauge {
  event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
  event ClaimRewards(address indexed from, address indexed reward, uint256 amount, address recepient);
  event Deposit(address indexed from, uint256 amount);
  event NotifyReward(address indexed from, address indexed reward, uint256 amount);
  event VeTokenLocked(address indexed account, uint256 tokenId);
  event VeTokenUnlocked(address indexed account, uint256 tokenId);
  event Withdraw(address indexed from, uint256 amount);

  function balanceOf(address) external view returns (uint256);

  function batchUpdateRewardPerToken(address token, uint256 maxRuns) external;

  function bribe() external view returns (address);

  function checkpoints(address, uint256) external view returns (uint256 timestamp, uint256 value);

  function claimFees() external returns (uint256 claimed0, uint256 claimed1);

  function deposit(uint256 amount, uint256 tokenId) external;

  function depositAll(uint256 tokenId) external;

  function derivedBalance(address account) external view returns (uint256);

  function derivedBalances(address) external view returns (uint256);

  function derivedSupply() external view returns (uint256);

  function earned(address token, address account) external view returns (uint256);

  function fees0() external view returns (uint256);

  function fees1() external view returns (uint256);

  function getPriorBalanceIndex(address account, uint256 timestamp) external view returns (uint256);

  function getPriorRewardPerToken(address token, uint256 timestamp) external view returns (uint256, uint256);

  function getPriorSupplyIndex(uint256 timestamp) external view returns (uint256);

  function getReward(address account, address[] memory tokens) external;

  function isRewardToken(address) external view returns (bool);

  function lastEarn(address, address) external view returns (uint256);

  function lastUpdateTime(address) external view returns (uint256);

  function left(address token) external view returns (uint256);

  function notifyRewardAmount(address token, uint256 amount) external;

  function numCheckpoints(address) external view returns (uint256);

  function operator() external view returns (address);

  function periodFinish(address) external view returns (uint256);

  function registerRewardToken(address token) external;

  function removeRewardToken(address token) external;

  function rewardPerToken(address token) external view returns (uint256);

  function rewardPerTokenCheckpoints(address, uint256) external view returns (uint256 timestamp, uint256 value);

  function rewardPerTokenNumCheckpoints(address) external view returns (uint256);

  function rewardPerTokenStored(address) external view returns (uint256);

  function rewardRate(address) external view returns (uint256);

  function rewardTokens(uint256) external view returns (address);

  function rewardTokensLength() external view returns (uint256);

  function supplyCheckpoints(uint256) external view returns (uint256 timestamp, uint256 value);

  function supplyNumCheckpoints() external view returns (uint256);

  function tokenIds(address) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function underlying() external view returns (address);

  function userRewardPerTokenStored(address, address) external view returns (uint256);

  function ve() external view returns (address);

  function voter() external view returns (address);

  function withdraw(uint256 amount) external;

  function withdrawAll() external;

  function withdrawToken(uint256 amount, uint256 tokenId) external;
}

