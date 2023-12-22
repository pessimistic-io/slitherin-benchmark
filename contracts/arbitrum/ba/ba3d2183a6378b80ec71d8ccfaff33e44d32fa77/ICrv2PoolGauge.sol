// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ICrv2PoolGauge {
  function deposit(
    uint256 _value,
    address _addr,
    bool _claim_rewards
  ) external;

  function withdraw(
    uint256 _value,
    address _addr,
    bool _claim_rewards
  ) external;

  function claim_rewards() external;

  function balanceOf(address _address) external returns (uint256);
}

