// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface IStrategy {
  function name() external view returns (string memory);
  function getSignal(address, uint256) external view returns (bool);
}

