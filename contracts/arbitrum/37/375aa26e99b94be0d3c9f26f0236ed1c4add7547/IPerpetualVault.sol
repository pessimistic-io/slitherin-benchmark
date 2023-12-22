// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface IPerpetualVault {
  function deposit(uint256 amount) external;
  function withdraw(uint256 amount) external returns (bool);
  function shares(address account) external view returns (uint256);
  function lookback() external view returns (uint256);
  function indexToken() external view returns (address);
  function hedgeToken() external view returns (address);
  function isLong() external view returns (bool);
  function isNextAction() external view returns (bool);
}

