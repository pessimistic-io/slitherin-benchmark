// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ManagerModifier.sol";
import "./ILootBoxDataStorage.sol";

contract LootBoxDataStorage is
  ILootBoxDataStorage,
  ManagerModifier,
  ReentrancyGuard,
  Pausable
{
  struct LootBoxData {
    uint256 tokenId;
    uint256 packedCharacteristics;
    uint16[16] characteristics;
  }

  uint256 lastItemTokenId;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256) packedCharacteristicsToTokenId;
  mapping(uint256 => LootBoxData) lootBoxes;

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    uint256 _lastItemTokenId,
    address _lootBoxCharacteristicDefinitions
  ) ManagerModifier(_manager) {
    lastItemTokenId = _lastItemTokenId;
  }

  //=======================================
  // External
  //=======================================
  function obtainTokenId(
    uint16[] memory _characteristics
  ) external onlyManager returns (uint256) {
    // Hash characteristics to check
    uint256 packed = packCharacteristics(_characteristics);

    // Returned a stored tokenId if there's one already
    if (packedCharacteristicsToTokenId[packed] != 0) {
      return packedCharacteristicsToTokenId[packed];
    }

    // Attach the hash to characteristics
    return save(packed, _characteristics);
  }

  function characteristics(
    uint256 _tokenId,
    uint16 _characteristicId
  ) external view returns (uint16) {
    return lootBoxes[_tokenId].characteristics[_characteristicId];
  }

  function characteristics(
    uint256 _tokenId
  ) external view returns (uint16[16] memory) {
    return lootBoxes[_tokenId].characteristics;
  }

  //=======================================
  // Internal
  //=======================================
  function packCharacteristics(
    uint16[] memory _characteristics
  ) internal pure returns (uint256) {
    uint256 output = 0;
    for (uint256 i = 0; i < _characteristics.length; i++) {
      uint256 shiftedValue = uint256(_characteristics[i]) << (i * 16);
      output |= shiftedValue;
    }

    return output;
  }

  function save(
    uint256 _packedCharacteristics,
    uint16[] memory _characteristics
  ) internal whenNotPaused onlyManager returns (uint256) {
    uint256 tokenId = packedCharacteristicsToTokenId[_packedCharacteristics];
    if (tokenId == 0) {
      tokenId = ++lastItemTokenId;
    }
    LootBoxData storage data = lootBoxes[tokenId];
    data.tokenId = tokenId;
    for (uint16 i = 0; i < _characteristics.length; i++) {
      data.characteristics[i] = _characteristics[i];
    }
    data.packedCharacteristics = _packedCharacteristics;

    packedCharacteristicsToTokenId[_packedCharacteristics] = tokenId;
    emit LootBoxUpdated(tokenId, data.characteristics);

    return tokenId;
  }
}

