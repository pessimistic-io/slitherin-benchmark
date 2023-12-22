// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRarityItemDataStorage.sol";
import "./ManagerModifier.sol";
import "./RarityItem.sol";
import "./RarityItemDataStorage.sol";
import "./RarityItemConstants.sol";

contract RarityItemDataStorage is
  IRarityItemDataStorage,
  ManagerModifier,
  ReentrancyGuard,
  Pausable
{
  //=======================================
  // Uints
  //=======================================
  uint256 public lastItemTokenId;

  //=======================================
  // Structs
  //=======================================
  struct RarityItemData {
    uint256 tokenId;
    uint256 packedCharacteristics;
    uint16[16] characteristics;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256) public characteristicsToTokenId;
  mapping(uint256 => RarityItemData) public tokenIdToItemData;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    uint256 _lastItemTokenId
  ) ManagerModifier(_manager) {
    lastItemTokenId = _lastItemTokenId;
  }

  //=======================================
  // External
  //=======================================
  function obtainTokenId(
    uint16[] memory _characteristics
  ) external onlyManager returns (uint256) {
    uint256 packed = _packCharacteristics(_characteristics);

    if (characteristicsToTokenId[packed] != 0) {
      return characteristicsToTokenId[packed];
    }

    return _save(packed, _characteristics);
  }

  function getPackedCharacteristics(
    uint256 _tokenId
  ) external view returns (uint256) {
    return tokenIdToItemData[_tokenId].packedCharacteristics;
  }

  function characteristics(
    uint256 _tokenId,
    uint16 _characteristicId
  ) external view returns (uint16) {
    return tokenIdToItemData[_tokenId].characteristics[_characteristicId];
  }

  function characteristics(
    uint256 _tokenId
  ) external view returns (uint16[16] memory) {
    return tokenIdToItemData[_tokenId].characteristics;
  }

  //=======================================
  // Admin
  //=======================================
  function preGenerateIds(
    uint16[][] calldata _multipleCharacteristics
  ) external onlyAdmin {
    for (uint16 i = 0; i < _multipleCharacteristics.length; i++) {
      uint256 packed = _packCharacteristics(_multipleCharacteristics[i]);

      if (characteristicsToTokenId[packed] == 0) {
        _save(packed, _multipleCharacteristics[i]);
      }
    }
  }

  function updateCharacteristics(
    uint256 tokenId,
    uint16[] calldata _newCharacteristics
  ) external onlyAdmin {
    // Check if the tokenId is already in use
    RarityItemData storage existingData = tokenIdToItemData[tokenId];
    require(existingData.tokenId != 0);

    // Release the tokenId for the existing data so that you can still create items with the old characteristics
    characteristicsToTokenId[existingData.packedCharacteristics] = 0;

    // Check that new packed characteristics are different and update if necessary
    uint256 packedCharacteristics = _packCharacteristics(_newCharacteristics);
    require(existingData.packedCharacteristics != packedCharacteristics);
    existingData.packedCharacteristics = packedCharacteristics;

    // Save new characteristics, while also checking if at least 1 characteristic is different
    bool isDifferent = false;
    for (uint256 i = 0; i < 16; i++) {
      // Some values might not be present in calldata
      uint16 newValue = i < _newCharacteristics.length
        ? _newCharacteristics[i]
        : 0;

      // Store the new value and
      if (existingData.characteristics[i] != newValue) {
        existingData.characteristics[i] = newValue;
        isDifferent = true;
      }
    }
    // Rollback if nothing changed
    require(
      isDifferent == true,
      "At least 1 characteristic should be different"
    );

    // If the new characteristics are not assigned to a tokenId yet - reassign them to the tokenId
    // If the new characteristics already have a tokenId then two tokenIds will have the same characteristics
    // It's encouraged to let the users burn their old tokens for new ones in this case
    if (characteristicsToTokenId[packedCharacteristics] == 0) {
      characteristicsToTokenId[packedCharacteristics] = tokenId;
    }
  }

  //=======================================
  // Internal
  //=======================================
  function _packCharacteristics(
    uint16[] memory _characteristics
  ) internal pure returns (uint256) {
    uint256 output = 0;
    for (uint256 i = 0; i < _characteristics.length; i++) {
      uint256 shiftedValue = uint256(_characteristics[i]) << (i * 16);
      output |= shiftedValue;
    }

    return output;
  }

  function _save(
    uint256 _packedCharacteristics,
    uint16[] memory _characteristics
  ) internal whenNotPaused onlyManager returns (uint256) {
    uint256 tokenId = characteristicsToTokenId[_packedCharacteristics];
    if (tokenId == 0) {
      tokenId = ++lastItemTokenId;
    }

    RarityItemData storage data = tokenIdToItemData[tokenId];
    data.tokenId = tokenId;
    for (uint16 i = 0; i < _characteristics.length; i++) {
      data.characteristics[i] = _characteristics[i];
    }
    data.packedCharacteristics = _packedCharacteristics;
    characteristicsToTokenId[_packedCharacteristics] = tokenId;
    emit RarityItemUpdated(tokenId, _characteristics);
    return tokenId;
  }
}

