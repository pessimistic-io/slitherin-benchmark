// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IGmxUtils.sol";
import "./Order.sol";

interface IPerpetualVault {
  function deposit(uint256 amount) external;
  function withdraw(address recipient, uint256 amount) external;
  function shares(address account) external view returns (uint256);
  function lookback() external view returns (uint256);
  function name() external view returns (string memory);
  function indexToken() external view returns (address);
  function collateralToken() external view returns (address);
  function isLong() external view returns (bool);
  function isNextAction() external view returns (bool);
  function isLock() external view returns (bool);
  function isBusy() external view returns (bool);
  function afterOrderExecution(bytes32 key, Order.OrderType, bool, bytes32) external;
  function afterOrderCancellation(bytes32 key, Order.OrderType, bool, bytes32) external;
}

