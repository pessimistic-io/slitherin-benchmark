// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IStructure {
  function data(
    uint256 _realmId,
    uint256 _type
  ) external view returns (uint256);

  function add(uint256 _realmId, uint256 _type, uint256 _amount) external;

  function remove(uint256 _realmId, uint256 _type, uint256 _amount) external;
}

