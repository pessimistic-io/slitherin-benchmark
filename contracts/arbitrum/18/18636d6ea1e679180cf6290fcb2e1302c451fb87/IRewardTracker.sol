// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8;

interface IRewardTracker {
  event Claim(address indexed receiver, uint256 amount);

  function stake(address _depositToken, uint256 _amount) external;

  function stakeForAccount(
    address _fundingAccount,
    address _account,
    address _depositToken,
    uint256 _amount
  ) external;

  function unstake(address _depositToken, uint256 _amount) external;

  function unstakeForAccount(
    address _account,
    address _depositToken,
    uint256 _amount,
    address _receiver
  ) external;

  function claim(address _receiver) external returns (uint256);

  function claimForAccount(address _account, address _receiver) external returns (uint256);

  function updateRewards() external;

  function depositBalances(address _account, address _depositToken) external view returns (uint256);

  function stakedAmounts(address _account) external view returns (uint256);

  function averageStakedAmounts(address _account) external view returns (uint256);

  function cumulativeRewards(address _account) external view returns (uint256);

  function claimable(address _account) external view returns (uint256);

  function tokensPerInterval() external view returns (uint256);
}

