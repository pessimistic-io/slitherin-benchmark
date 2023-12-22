// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IProduction {
  function setProduction(uint256 _realmId, uint256 _timestamp) external;

  function isProductive(uint256 _realmId) external view returns (bool);

  function getStartedAt(uint256 _realmId) external view returns (uint256);
}

