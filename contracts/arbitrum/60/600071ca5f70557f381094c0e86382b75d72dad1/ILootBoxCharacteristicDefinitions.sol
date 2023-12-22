// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

uint16 constant LOOTBOX_CHARACTERISTIC_TYPE = 0;
uint16 constant LOOTBOX_CHARACTERISTIC_ORIGIN = 1;

interface ILootBoxCharacteristicDefinitions {
  function characteristics(uint16 _id) external view returns (string memory);

  function characteristicCount() external view returns (uint16);

  function types(uint16 _typeId) external view returns (string memory);

  function allTypeIndexes() external view returns (uint16[] memory);

  function origins(uint16 _origin) external view returns (string memory);
}

