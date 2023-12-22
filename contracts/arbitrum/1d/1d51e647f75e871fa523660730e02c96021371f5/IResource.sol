// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IResource {
  function data(
    uint256 _realmId,
    uint256 _resourceId
  ) external view returns (uint256);

  function add(uint256 _realmId, uint256 _resourceId, uint256 _amount) external;

  function remove(
    uint256 _realmId,
    uint256 _resourceId,
    uint256 _amount
  ) external;
}

