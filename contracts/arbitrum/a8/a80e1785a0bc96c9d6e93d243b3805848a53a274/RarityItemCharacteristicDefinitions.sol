// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./ManagerModifier.sol";
import "./RarityItemConstants.sol";
import "./TraitConstants.sol";
import "./IRarityItemCharacteristicDefinitions.sol";

contract RarityItemCharacteristicDefinitions is
  IRarityItemCharacteristicDefinitions,
  ManagerModifier
{
  //=======================================
  // Strings
  //=======================================
  string[] public characteristics;
  string[][] public characteristicValues;

  //=======================================
  // Item characteristics
  //=======================================
  string[] public ITEM_CHARACTERISTICS = [
    "Rarity",
    "Slot",
    "Type",
    "Subtype",
    "Prefix",
    "Suffix"
  ];

  //=======================================
  // Item rarities
  //=======================================
  string[] public ITEM_RARITIES = [
    "",
    "Common",
    "Rare",
    "Epic",
    "Legendary",
    "Mythic",
    "Exotic"
  ];

  //=======================================
  // Item slots
  //=======================================
  string[] public ITEM_SLOTS = ["", "Head", "Chest", "Hand", "Accessory"];

  //=======================================
  // Item types
  //=======================================
  string[] public ITEM_CATEGORIES = [
    "",
    "Headgear",
    "Armor",
    "Apparel",
    "Jewelry",
    "Weapon"
  ];

  //=======================================
  // Item subtypes
  //=======================================
  string[] public ITEM_TYPES = [
    "Longsword",
    "Claymore",
    "Morning Star",
    "Dagger",
    "Trident",
    "Mace",
    "Spear",
    "Axe",
    "Hammer",
    "Tomahawk",
    "Visor",
    "Necklace",
    "Amulet",
    "Pendant",
    "Earrings",
    "Glasses",
    "Mask",
    "Helmet",
    "Cloak",
    "Ring",
    "Gloves",
    "Body Armor"
  ];

  //=======================================
  // Prefix / suffix definitions
  //=======================================
  string[] public ITEM_PREFIXES = [
    // 0 - NO PREFIX
    "",
    "Faceless",
    "Rumored",
    "Eminent",
    "Fabled"
  ];

  string[] public ITEM_SUFFIXES = [""];

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {
    // Characteristic names
    characteristics = ITEM_CHARACTERISTICS;

    // Set initial characteristics values
    characteristicValues = new string[][](6);
    characteristicValues[ITEM_CHARACTERISTIC_RARITY] = ITEM_RARITIES;
    characteristicValues[ITEM_CHARACTERISTIC_SLOT] = ITEM_SLOTS;
    characteristicValues[ITEM_CHARACTERISTIC_CATEGORY] = ITEM_CATEGORIES;
    characteristicValues[ITEM_CHARACTERISTIC_TYPE] = ITEM_TYPES;
    characteristicValues[ITEM_CHARACTERISTIC_PREFIX] = ITEM_PREFIXES;
    characteristicValues[ITEM_CHARACTERISTIC_SUFFIX] = ITEM_SUFFIXES;
  }

  //=======================================
  // External
  //=======================================
  function characteristicNames(
    uint16 _characteristic
  ) external view returns (string memory) {
    return characteristics[_characteristic];
  }

  function getCharacteristicValues(
    uint16 _characteristic,
    uint16 _id
  ) external view returns (string memory) {
    return characteristicValues[_characteristic][_id];
  }

  function characteristicValuesCount(
    uint16 _characteristic
  ) external view returns (uint16) {
    return uint16(characteristicValues[_characteristic].length);
  }

  function allCharacteristicValues(
    uint16 _characteristic
  ) external view returns (string[] memory) {
    return characteristicValues[_characteristic];
  }

  function characteristicCount() external view returns (uint16) {
    return uint16(characteristics.length);
  }

  function updateCharacteristicValues(
    uint16 _characteristic,
    string[] memory _newValues
  ) external onlyAdmin {
    characteristicValues[_characteristic] = _newValues;
  }
}

