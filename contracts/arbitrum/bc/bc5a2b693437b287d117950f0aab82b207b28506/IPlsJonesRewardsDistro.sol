// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IPlsJonesRewardsDistro {
  function updateHarvestDetails(uint256 _timestamp, uint256 _jones) external;
}

