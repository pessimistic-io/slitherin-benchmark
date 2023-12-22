// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IPopulation {
  function getPopulation(uint256 _realmId) external view returns (uint256);
}

