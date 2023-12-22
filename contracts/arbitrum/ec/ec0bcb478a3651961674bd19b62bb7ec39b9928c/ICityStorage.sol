// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface ICityStorage {
  function build(uint256 _realmId, uint256 _hours) external;

  function addNourishmentCredit(uint256 _realmId, uint256 _amount) external;

  function removeNourishmentCredit(uint256 _realmId, uint256 _amount) external;

  function canBuild(uint256 _realmId) external view returns (bool);
}

