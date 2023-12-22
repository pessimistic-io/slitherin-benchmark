// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IERC20.sol";

abstract contract IBaseRewardPool {
  IERC20 public stakingToken;

  function setParams(
    uint256 _pid,
    address _stakingToken,
    address _rewardToken
  ) external virtual;

  function totalSupply() external view virtual returns (uint256);

  function balanceOf(address account) external view virtual returns (uint256);

  function stake(uint256) external virtual;

  function stakeAll() external virtual;

  function stakeFor(address, uint256) external virtual;

  function withdraw(uint256) external virtual;

  function withdrawAll() external virtual;

  function donate(address, uint256) external payable virtual;

  function earned(address, address) external view virtual returns (uint256);

  function getUserAmountTime(address) external view virtual returns (uint256);

  function getRewardTokens() external view virtual returns (address[] memory);

  function getRewardTokensLength() external view virtual returns (uint256);

  function getReward(address) external virtual;

  function withdrawFor(address _account, uint256 _amount) external virtual;

  event BoosterUpdated(address _booster);
  event RewardTokenAdded(address indexed _rewardToken);
  event Staked(address indexed _user, uint256 _amount);
  event Withdrawn(address indexed _user, uint256 _amount);
  event EmergencyWithdrawn(address indexed _user, uint256 _amount);
  event RewardPaid(
    address indexed _user,
    address indexed _rewardToken,
    uint256 _reward
  );
}

