// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "./IERC20.sol";

/// @title  IWrappedStakedJonesToken
/// @author Savvy DeFi
interface IWrappedStakedJonesToken {
  function token() external view returns (address);

  function baseToken() external view returns (address);

  function rewardToken() external view returns (address);

  function stipArbRewarder() external view returns (address);

  function stakePoolId() external view returns (uint256);

  function price() external view returns (uint256);

  function deposit(
    uint256 amount,
    address recipient
  ) external returns (uint256);

  function withdraw(
    uint256 amount,
    address recipient
  ) external returns (uint256);

  function claim() external returns (uint256);
}

