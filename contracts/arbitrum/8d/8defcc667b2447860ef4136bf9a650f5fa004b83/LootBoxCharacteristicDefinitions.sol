// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./Strings.sol";

import "./ManagerModifier.sol";
import "./ILootBoxCharacteristicDefinitions.sol";

contract LootBoxCharacteristicDefinitions is ILootBoxCharacteristicDefinitions {
  //=======================================
  // Characteristic names
  //=======================================
  mapping(uint16 => string) public characteristics;

  //=======================================
  // Lootbox rarity names
  //=======================================
  mapping(uint16 => string) public types;
  uint16[] public typeIndexes;

  //=======================================
  // Constructor
  //=======================================
  constructor() {
    // Characteristic names
    toMapping(LOOTBOX_CHARACTERISTICS, characteristics);

    // Lootbox rarity names
    toMapping(LOOTBOX_TYPES, types);
    typeIndexes = toIndexesArray(LOOTBOX_TYPES.length);
  }

  //=======================================
  // Lootbox characteristics
  //=======================================

  string[] public LOOTBOX_CHARACTERISTICS = ["Rarity", "Origin"];

  string[] public LOOTBOX_TYPES = ["Common", "Rare", "Epic", "Legendary"];

  function toMapping(
    string[] memory _nameArray,
    mapping(uint16 => string) storage newMapping
  ) internal {
    for (uint16 i = 0; i < _nameArray.length; i++) {
      newMapping[i] = _nameArray[i];
    }
  }

  function toIndexesArray(
    uint256 length
  ) internal pure returns (uint16[] memory) {
    uint16[] memory arr = new uint16[](length);
    for (uint16 i = 0; i < length; i++) {
      arr[i] = i;
    }
    return arr;
  }

  function characteristicCount() external view returns (uint16) {
    return uint16(LOOTBOX_CHARACTERISTICS.length);
  }

  function allTypeIndexes() external view returns (uint16[] memory) {
    return typeIndexes;
  }

  function origins(uint16 _origin) external pure returns (string memory) {
    return Strings.toString(_origin);
  }
}

