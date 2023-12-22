pragma solidity ^0.8.0;

interface IGaugeStaker {
  function deposit(address gauge, uint256 amount) external;

  function deposit(uint256 amount) external;

  function withdraw(address gauge, uint256 amount) external;

  function harvestRewards(address gauge, address[] calldata tokens) external;

  function claimGaugeReward(address _gauge) external;

  function lockHarvestAmount(address _gauge, uint256 _amount) external;
}

