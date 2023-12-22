// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./IItemDataStorage.sol";

interface IRarityItemDataStorage is IItemDataStorage {
  event RarityItemUpdated(uint256 _tokenId, uint16[] characteristics);

  function getPackedCharacteristics(
    uint256 _tokenId
  ) external view returns (uint256);
}

