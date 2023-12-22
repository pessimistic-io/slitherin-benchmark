// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./Strings.sol";
import "./Base64.sol";

import "./ManagerModifier.sol";
import "./IItemMetadata.sol";
import "./MetadataUtils.sol";
import "./ILootBoxCharacteristicDefinitions.sol";
import "./LootBoxCharacteristicDefinitions.sol";
import "./ILootBoxDataStorage.sol";

contract LootBoxMetadata is IItemMetadata, ManagerModifier {
  using Strings for uint256;

  //=======================================
  // Interfaces
  //=======================================
  ILootBoxCharacteristicDefinitions public characteristicDefinitions;
  ILootBoxDataStorage public lootBoxData;

  //=======================================
  // Strings
  //=======================================
  string public baseURI;
  string public collectionName;
  string public collectionDescription;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _lootBoxDataStorage,
    address _lootBoxCharacteristicDefinitions
  ) ManagerModifier(_manager) {
    lootBoxData = ILootBoxDataStorage(_lootBoxDataStorage);
    characteristicDefinitions = ILootBoxCharacteristicDefinitions(
      _lootBoxCharacteristicDefinitions
    );
    collectionName = "Realm LootBoxes";
    collectionDescription = "Realm LootBoxes description";
  }

  //=======================================
  // External
  //=======================================
  function getMetadata(uint256 _tokenId) external view returns (string memory) {
    return
      metadata.convertToMetadata(
        collectionName,
        collectionDescription,
        string.concat(baseURI, Strings.toString(_tokenId), ".jpeg"),
        _attributeKeys(),
        _attributeValues(_tokenId)
      );
  }

  function isBound(uint256 _tokenId) external pure returns (bool) {
    return false;
  }

  function name(uint256 _tokenId) external view returns (string memory) {
    uint16 lootBoxType = lootBoxData.characteristics(
      _tokenId,
      LOOTBOX_CHARACTERISTIC_TYPE
    );

    return
      string.concat(characteristicDefinitions.types(lootBoxType), " LootBox");
  }

  //=======================================
  // Admin
  //=======================================
  function setBaseURI(string calldata _baseURI) external onlyAdmin {
    baseURI = _baseURI;
  }

  function setCollectionName(string calldata _name) external onlyAdmin {
    collectionName = _name;
  }

  function setCollectionDescription(
    string calldata _description
  ) external onlyAdmin {
    collectionDescription = _description;
  }

  function updateDataStorage(address _addr) external onlyAdmin {
    lootBoxData = ILootBoxDataStorage(_addr);
  }

  //=======================================
  // Internal
  //=======================================
  // Lists all metadata attributes
  function _attributeKeys() internal view returns (string[] memory) {
    // The metadata contains all the stored characteristics
    uint16 count = characteristicDefinitions.characteristicCount();

    // Prepare array of metadata property names + the item name
    string[] memory keys = new string[](count + 1);
    for (uint16 i = 0; i < count; i++) {
      keys[i] = characteristicDefinitions.characteristics(i);
    }

    // We don't store the name in the definitions for storage efficiency
    keys[count] = "Name";

    return keys;
  }

  // Lists all metadata attributes
  function _attributeValues(
    uint256 _tokenId
  ) internal view returns (string[] memory) {
    // Get the characteristics from the contract
    uint16[16] memory lootBoxCharacteristics = lootBoxData.characteristics(
      _tokenId
    );

    // The metadata contains all the stored characteristics
    uint256 count = characteristicDefinitions.characteristicCount();

    // Prepare array of metadata property values + the item name
    string[] memory values = new string[](count + 1);
    values[LOOTBOX_CHARACTERISTIC_TYPE] = characteristicDefinitions.types(
      lootBoxCharacteristics[LOOTBOX_CHARACTERISTIC_TYPE]
    );
    values[count] = string.concat(
      values[LOOTBOX_CHARACTERISTIC_TYPE],
      " LootBox"
    );

    return values;
  }
}

