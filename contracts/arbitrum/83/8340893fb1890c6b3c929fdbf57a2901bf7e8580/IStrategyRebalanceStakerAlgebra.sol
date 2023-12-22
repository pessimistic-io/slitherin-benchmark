// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStrategyRebalanceStakerAlgebra {
  function harvest() external;

  function inRangeCalc() external view returns (bool);

  function lastHarvest() external view returns (uint256);

  function rebalance() external;
}

