// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TreasureMetadataStoreState.sol";

interface ITreasureMetadataStore {
    // Sets the metadata for the given Ids.
    // Admin only.
    function setMetadataForIds(uint256[] calldata _ids, TreasureMetadata[] calldata _metadatas) external;

    // Returns if the given ID has metadata set.
    function hasMetadataForTreasureId(uint256 _treasureId) external view returns(bool);

    // Returns the metadata for the given ID. Reverts if no metadata for the ID is set.
    function getMetadataForTreasureId(uint256 _treasureId) external view returns(TreasureMetadata memory);

    // For the given tier, gets a random MINTABLE treasure id.
    function getRandomTreasureForTier(uint8 _tier, uint256 _randomNumber) external view returns(uint256);

    // For the given tier AND category, gets a random MINTABLE treasure id.
    function getRandomTreasureForTierAndCategory(
        uint8 _tier,
        TreasureCategory _category,
        uint256 _randomNumber)
    external view returns(uint256);

    // For the given tier, gets a random treasure id, MINTABLE OR NOT.
    function getAnyRandomTreasureForTier(uint8 _tier, uint256 _randomNumber) external view returns(uint256);
}

// Do not change. Stored in state.
struct TreasureMetadata {
    TreasureCategory category;
    uint8 tier;
    // Out of 100,000
    uint32 craftingBreakOdds;
    bool isMintable;
    uint256 consumableIdDropWhenBreak;
}

enum TreasureCategory {
    ALCHEMY,
    ARCANA,
    BREWING,
    ENCHANTER,
    LEATHERWORKING,
    SMITHING
}
