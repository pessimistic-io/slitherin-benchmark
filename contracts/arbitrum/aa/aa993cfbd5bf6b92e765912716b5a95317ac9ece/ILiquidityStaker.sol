// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

struct StakerBalance {
  uint256 cap;
  uint256 partiallyVestedBalance;
  uint256 fullyVestedBalance;
  uint256 cappedDepositedBalance;
  uint256 uncappedDepositedBalance;
  uint256 walletBalance;
  uint256 totalUncappedBalance;
}

interface ILiquidityStaker {
  function stake(uint256 _amount) external;

  function unstake(
    uint256[] calldata _stakedDepositIndex,
    uint256[] calldata _amount
  ) external;

  function currentStatusTotal(
    address staker,
    uint256 cap
  ) external view returns (StakerBalance memory balance);
}

