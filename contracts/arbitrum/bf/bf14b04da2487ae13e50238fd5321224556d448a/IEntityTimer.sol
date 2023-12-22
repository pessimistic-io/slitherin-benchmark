// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IEntityTimer {
  function build(uint256 _realmId, uint256 _hours) external;

  function canBuild(uint256 _realmId) external view returns (bool);
}

