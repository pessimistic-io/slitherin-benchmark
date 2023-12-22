// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./Strings.sol";
import "./Base64.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ManagerModifier.sol";

import "./RarityItem.sol";
import "./IRarityItemMinter.sol";
import "./IRarityItemDataStorage.sol";
import "./IRarityItemMetadata.sol";
import "./IRarityItemCharacteristicDefinitions.sol";
import "./RarityItemCharacteristicDefinitions.sol";

import "./IItemMetadata.sol";
import "./Random.sol";

contract RarityItemMinter is
  IRarityItemMinter,
  ManagerModifier,
  ReentrancyGuard,
  Pausable
{
  //=======================================
  // Interfaces
  //=======================================
  IRarityItemCharacteristicDefinitions public characteristicDefinitions;
  IRarityItemDataStorage public dataStorage;
  IRarityItemMetadata public metadata;
  RarityItem public rarityItem;

  //=======================================
  // Uints
  //=======================================
  // Available Item definitions slots -> types -> subtypes
  uint16[] public slots;
  uint16[][] public categories;
  uint16[][][] public types;

  // Available Prefix/Suffix by rarity
  uint16[][] public prefixes;
  uint16[][] public suffixes;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _itemCharacteristicDefinitions,
    address _dataStorage,
    address _metadata,
    address _rarityItem
  ) ManagerModifier(_manager) {
    characteristicDefinitions = IRarityItemCharacteristicDefinitions(
      _itemCharacteristicDefinitions
    );
    dataStorage = IRarityItemDataStorage(_dataStorage);
    rarityItem = RarityItem(_rarityItem);
    metadata = IRarityItemMetadata(_metadata);

    slots = [1, 2, 3, 4];
    categories = new uint16[][](slots.length);
    types = new uint16[][][](slots.length);

    categories[0] = [ITEM_TYPE_HEADGEAR];
    types[0] = new uint16[][](1);
    types[0][0] = [10, 15, 16, 17];
    //
    categories[1] = [ITEM_TYPE_ARMOR, ITEM_TYPE_APPAREL];
    types[1] = new uint16[][](2);
    types[1][0] = [21];
    types[1][1] = [18];

    categories[2] = [ITEM_TYPE_WEAPON];
    types[2] = new uint16[][](1);
    types[2][0] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

    categories[3] = [ITEM_TYPE_JEWELRY, ITEM_TYPE_APPAREL];
    types[3] = new uint16[][](2);
    types[3][0] = [11, 12, 13, 14, 19];
    types[3][1] = [20];

    prefixes = new uint16[][](5);
    suffixes = new uint16[][](5);
    prefixes[0] = [0];
    suffixes[0] = [0];

    prefixes[ITEM_RARITY_COMMON] = [1];
    suffixes[ITEM_RARITY_COMMON] = [0];
    //
    prefixes[ITEM_RARITY_RARE] = [2];
    suffixes[ITEM_RARITY_RARE] = [0];
    //
    prefixes[ITEM_RARITY_EPIC] = [3];
    suffixes[ITEM_RARITY_EPIC] = [0];
    //
    prefixes[ITEM_RARITY_LEGENDARY] = [4];
    suffixes[ITEM_RARITY_LEGENDARY] = [0];
  }

  //=========================================
  // External
  //=========================================
  function mintSpecific(
    uint256 _tokenId,
    address _recipient,
    uint256 amount
  ) external onlyMinter whenNotPaused {
    string memory name = metadata.name(_tokenId);

    rarityItem.mintFor(_recipient, _tokenId, amount);

    emit RarityItemMinted(_tokenId, name, _recipient, amount);
  }

  function mintRandom(
    uint16 _rarity,
    uint256 _randomBase,
    address _recipient
  ) external onlyMinter whenNotPaused returns (uint256, uint256, address) {
    uint16[] memory characteristics = new uint16[](7);
    characteristics[ITEM_CHARACTERISTIC_RARITY] = _rarity;
    (
      _randomBase,
      characteristics[ITEM_CHARACTERISTIC_SLOT],
      characteristics[ITEM_CHARACTERISTIC_CATEGORY],
      characteristics[ITEM_CHARACTERISTIC_TYPE],
      characteristics[ITEM_CHARACTERISTIC_PREFIX],
      characteristics[ITEM_CHARACTERISTIC_SUFFIX]
    ) = _randomBaseCharacteristics(_randomBase, _rarity);

    uint256 tokenId = dataStorage.obtainTokenId(characteristics);
    _mint(_recipient, tokenId);
    return (_randomBase, tokenId, address(rarityItem));
  }

  function mintCharacteristics(
    address _recipient,
    uint16 _rarity,
    uint16 _slot,
    uint16 _category,
    uint16 _type,
    uint16 _prefix,
    uint16 _suffix
  ) external onlyMinter whenNotPaused returns (uint256, address) {
    uint16[] memory characteristics = new uint16[](7);
    characteristics[ITEM_CHARACTERISTIC_RARITY] = _rarity;
    characteristics[ITEM_CHARACTERISTIC_SLOT] = _slot;
    characteristics[ITEM_CHARACTERISTIC_CATEGORY] = _category;
    characteristics[ITEM_CHARACTERISTIC_TYPE] = _type;
    characteristics[ITEM_CHARACTERISTIC_PREFIX] = _prefix;
    characteristics[ITEM_CHARACTERISTIC_SUFFIX] = _suffix;

    uint256 tokenId = dataStorage.obtainTokenId(characteristics);
    _mint(_recipient, tokenId);
    return (tokenId, address(rarityItem));
  }

  //=======================================
  // Admin
  //=======================================
  function updateSlots(uint16[] memory _slots) external onlyAdmin {
    slots = _slots;
  }

  function updateCategories(uint16[][] memory _categories) external onlyAdmin {
    categories = _categories;
  }

  function updateTypes(uint16[][][] memory _types) external onlyAdmin {
    types = _types;
  }

  function updatePrefixes(uint16[][] memory _prefixes) external onlyAdmin {
    prefixes = _prefixes;
  }

  function updateSuffixes(uint16[][] memory _suffixes) external onlyAdmin {
    suffixes = _suffixes;
  }

  function setCharacteristicDefinitions(
    address _newCharacteristics
  ) external onlyAdmin {
    characteristicDefinitions = IRarityItemCharacteristicDefinitions(
      _newCharacteristics
    );
  }

  function updateMetadata(address _addr) external onlyAdmin {
    metadata = IRarityItemMetadata(_addr);
  }

  //=========================================
  // Internal
  //=========================================
  function _mint(address _recipient, uint256 _tokenId) internal {
    string memory name = metadata.name(_tokenId);
    rarityItem.mintFor(_recipient, _tokenId, 1);
    emit RarityItemMinted(_tokenId, name, _recipient, 1);
  }

  function _randomBaseCharacteristics(
    uint256 _randomBase,
    uint16 _rarity
  )
    internal
    view
    returns (
      uint256 newBase,
      uint16 itemSlot,
      uint16 itemType,
      uint16 itemSubType,
      uint16 itemPrefix,
      uint16 itemSuffix
    )
  {
    uint256 slotRoll;

    (slotRoll, _randomBase) = Random.getNextRandom(_randomBase, slots.length);
    itemSlot = slots[slotRoll];
    uint16[] storage possibleCategories = categories[slotRoll];

    uint256 roll;
    (roll, _randomBase) = Random.getNextRandom(
      _randomBase,
      possibleCategories.length
    );
    itemType = possibleCategories[roll];

    uint16[] storage possibleTypes = types[slotRoll][roll];
    (roll, _randomBase) = Random.getNextRandom(
      _randomBase,
      possibleTypes.length
    );
    itemSubType = possibleTypes[roll];

    uint16[] storage possiblePrefixes = prefixes[_rarity];
    (roll, _randomBase) = Random.getNextRandom(
      _randomBase,
      possiblePrefixes.length
    );
    itemPrefix = possiblePrefixes[roll];

    uint16[] storage possibleSuffixes = suffixes[_rarity];
    (roll, newBase) = Random.getNextRandom(
      _randomBase,
      possibleSuffixes.length
    );
    itemSuffix = possibleSuffixes[roll];
  }

  function _randomPrefixSuffix(
    uint16 _rarity,
    uint256 _randomBase
  ) internal view returns (uint256, uint16, uint16) {
    (uint256 prefixBase, uint16 itemPrefix) = _randomPrefix(
      _randomBase,
      _rarity
    );
    (uint256 suffixBase, uint16 itemSuffix) = _randomSuffix(
      prefixBase,
      _rarity
    );
    return (suffixBase, itemPrefix, itemSuffix);
  }

  function _randomPrefix(
    uint256 _randomBase,
    uint16 rarity
  ) internal view returns (uint256, uint16) {
    if (prefixes[rarity].length <= 0) {
      return (_randomBase, 0);
    }
    (uint256 prefixRoll, uint256 prefixBase) = Random.getNextRandom(
      _randomBase,
      prefixes[rarity].length
    );
    return (prefixBase, prefixes[rarity][prefixRoll]);
  }

  function _randomSuffix(
    uint256 _randomBase,
    uint16 rarity
  ) internal view returns (uint256, uint16) {
    if (suffixes[rarity].length <= 0) {
      return (_randomBase, 0);
    }
    (uint256 suffixRoll, uint256 suffixBase) = Random.getNextRandom(
      _randomBase,
      suffixes[rarity].length
    );
    return (suffixBase, suffixes[rarity][suffixRoll]);
  }
}

