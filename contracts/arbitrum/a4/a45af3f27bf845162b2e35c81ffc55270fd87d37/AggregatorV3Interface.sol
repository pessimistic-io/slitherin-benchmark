// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);
  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

