// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./Strings.sol";
import "./Base64.sol";

import "./ManagerModifier.sol";
import "./IItemMetadata.sol";
import "./MetadataUtils.sol";
import "./RarityItemConstants.sol";
import "./IRarityItemCharacteristicDefinitions.sol";
import "./RarityItemCharacteristicDefinitions.sol";
import "./IRarityItemDataStorage.sol";

contract RarityItemMetadata is IItemMetadata, ManagerModifier {
  using Strings for uint256;

  //=======================================
  // Immutables
  //=======================================
  IRarityItemDataStorage public immutable ITEM_DATA;

  //=======================================
  // Interfaces
  //=======================================
  IRarityItemCharacteristicDefinitions public characteristicDefinitions;

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
    address _itemDataStorage,
    address _itemCharacteristicDefinitions
  ) ManagerModifier(_manager) {
    ITEM_DATA = IRarityItemDataStorage(_itemDataStorage);

    characteristicDefinitions = IRarityItemCharacteristicDefinitions(
      _itemCharacteristicDefinitions
    );

    collectionName = ITEM_COLLECTION_NAME;
    collectionDescription = ITEM_COLLECTION_DESCRIPTION;
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
    uint16[16] memory itemCharacteristics = ITEM_DATA.characteristics(_tokenId);
    return _generateName(itemCharacteristics);
  }

  //=======================================
  // Admin
  //=======================================
  function setBaseURI(string calldata _baseURI) external onlyAdmin {
    baseURI = _baseURI;
  }

  function setCollectionName(
    string calldata _collectionName
  ) external onlyAdmin {
    collectionName = _collectionName;
  }

  function setCollectionDescription(
    string calldata _collectionDescription
  ) external onlyAdmin {
    collectionDescription = _collectionDescription;
  }

  function setCharacteristicDefinitions(
    address _newCharacteristics
  ) external onlyAdmin {
    characteristicDefinitions = IRarityItemCharacteristicDefinitions(
      _newCharacteristics
    );
  }

  //=======================================
  // Internal
  //=======================================
  function _attributeKeys() internal view returns (string[] memory) {
    uint256 count = characteristicDefinitions.characteristicCount();
    string[] memory keys = new string[](count + 1);
    for (uint16 i = 0; i < count; i++) {
      keys[i] = characteristicDefinitions.characteristicNames(i);
    }
    keys[count] = "Name";
    return keys;
  }

  function _attributeValues(
    uint256 _tokenId
  ) internal view returns (string[] memory) {
    uint16[16] memory itemCharacteristics = ITEM_DATA.characteristics(_tokenId);
    uint16 count = characteristicDefinitions.characteristicCount();
    string[] memory values = new string[](count + 1);
    values[ITEM_CHARACTERISTIC_RARITY] = characteristicDefinitions
      .getCharacteristicValues(
        ITEM_CHARACTERISTIC_RARITY,
        itemCharacteristics[ITEM_CHARACTERISTIC_RARITY]
      );
    values[ITEM_CHARACTERISTIC_SLOT] = characteristicDefinitions
      .getCharacteristicValues(
        ITEM_CHARACTERISTIC_SLOT,
        itemCharacteristics[ITEM_CHARACTERISTIC_SLOT]
      );
    values[ITEM_CHARACTERISTIC_CATEGORY] = characteristicDefinitions
      .getCharacteristicValues(
        ITEM_CHARACTERISTIC_CATEGORY,
        itemCharacteristics[ITEM_CHARACTERISTIC_CATEGORY]
      );
    values[ITEM_CHARACTERISTIC_TYPE] = characteristicDefinitions
      .getCharacteristicValues(
        ITEM_CHARACTERISTIC_TYPE,
        itemCharacteristics[ITEM_CHARACTERISTIC_TYPE]
      );
    values[ITEM_CHARACTERISTIC_PREFIX] = characteristicDefinitions
      .getCharacteristicValues(
        ITEM_CHARACTERISTIC_PREFIX,
        itemCharacteristics[ITEM_CHARACTERISTIC_PREFIX]
      );
    values[ITEM_CHARACTERISTIC_SUFFIX] = characteristicDefinitions
      .getCharacteristicValues(
        ITEM_CHARACTERISTIC_SUFFIX,
        itemCharacteristics[ITEM_CHARACTERISTIC_SUFFIX]
      );
    values[count] = _generateName(itemCharacteristics);
    return values;
  }

  function _generateName(
    uint16[16] memory _characteristics
  ) internal view returns (string memory) {
    // Get name from definitions
    string memory base = characteristicDefinitions.getCharacteristicValues(
      ITEM_CHARACTERISTIC_TYPE,
      _characteristics[ITEM_CHARACTERISTIC_TYPE]
    );
    string memory prefix = characteristicDefinitions.getCharacteristicValues(
      ITEM_CHARACTERISTIC_PREFIX,
      _characteristics[ITEM_CHARACTERISTIC_PREFIX]
    );
    string memory suffix = characteristicDefinitions.getCharacteristicValues(
      ITEM_CHARACTERISTIC_SUFFIX,
      _characteristics[ITEM_CHARACTERISTIC_SUFFIX]
    );

    // Both prefix and suffix
    if (bytes(suffix).length > 0 && bytes(prefix).length > 0) {
      return string.concat(prefix, " ", base, " ", suffix);
    }
    // No prefix, only suffix
    if (bytes(prefix).length > 0) {
      return string.concat(prefix, " ", base);
    }
    // No suffix, only prefix
    if (bytes(suffix).length > 0) {
      return string.concat(base, " ", suffix);
    }
    // Fallback for no prefix/suffix
    return base;
  }
}

