// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

interface IRarityItemCharacteristicDefinitions {
  function characteristicCount() external view returns (uint16);

  function characteristicNames(
    uint16 _characteristic
  ) external view returns (string memory);

  function getCharacteristicValues(
    uint16 _characteristic,
    uint16 _id
  ) external view returns (string memory);

  function characteristicValuesCount(
    uint16 _characteristic
  ) external view returns (uint16);

  function allCharacteristicValues(
    uint16 _characteristic
  ) external view returns (string[] memory);
}

