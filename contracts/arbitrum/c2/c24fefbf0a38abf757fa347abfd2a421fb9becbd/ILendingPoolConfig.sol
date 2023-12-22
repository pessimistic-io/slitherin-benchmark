// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILendingPoolConfig {
  function interestRateAPR(uint256 _debt, uint256 _floating) external view returns (uint256);
  function interestRatePerSecond(uint256 _debt, uint256 _floating) external view returns (uint256);
}

