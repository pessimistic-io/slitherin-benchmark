// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IData {
  function data(
    uint256 _realmId,
    uint256 _type
  ) external view returns (uint256);

  function collect(uint256 _realmId) external;

  function addToBuildQueue(
    uint256 _realmId,
    uint256 _queueSlot,
    uint256 _hours
  ) external;

  function addGoldSupply(uint256 _realmId, uint256 _gold) external;

  function add(uint256 _realmId, uint256 _type, uint256 _amount) external;

  function remove(uint256 _realmId, uint256 _type, uint256 _amount) external;

  function addBonus(uint256 _realmId, uint256 _type, uint256 _amount) external;

  function removeBonus(
    uint256 _realmId,
    uint256 _type,
    uint256 _amount
  ) external;

  function addDataName(uint256 _type, string memory _name) external;
}

