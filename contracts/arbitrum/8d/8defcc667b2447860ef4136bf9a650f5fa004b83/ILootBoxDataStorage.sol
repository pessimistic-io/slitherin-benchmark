// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

import "./IItemDataStorage.sol";

interface ILootBoxDataStorage is IItemDataStorage {
  event LootBoxUpdated(uint256 _tokenId, uint16[16] characteristics);
}

