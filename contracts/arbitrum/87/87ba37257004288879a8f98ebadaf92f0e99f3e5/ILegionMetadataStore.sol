// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// import "./LegionMetadataStoreState.sol";

interface ILegionMetadataStore {
    // Sets the intial metadata for a token id.
    // Admin only.
    function setInitialMetadataForLegion(
        address _owner,
        uint256 _tokenId,
        LegionGeneration _generation,
        LegionClass _class,
        LegionRarity _rarity,
        uint256 _oldId
    ) external;

    // // Increases the quest level by one. It is up to the calling contract to regulate the max quest level. No validation.
    // // Admin only.
    // function increaseQuestLevel(uint256 _tokenId) external;

    // // Increases the craft level by one. It is up to the calling contract to regulate the max craft level. No validation.
    // // Admin only.
    // function increaseCraftLevel(uint256 _tokenId) external;

    // // Increases the rank of the given constellation to the given number. It is up to the calling contract to regulate the max constellation rank. No validation.
    // // Admin only.
    // function increaseConstellationRank(
    //     uint256 _tokenId,
    //     Constellation _constellation,
    //     uint8 _to
    // ) external;

    // // Returns the metadata for the given legion.
    // function metadataForLegion(uint256 _tokenId)
    //     external
    //     view
    //     returns (LegionMetadata memory);

    // // Returns the tokenUri for the given token.
    // function tokenURI(uint256 _tokenId) external view returns (string memory);

    // Returns the generation and rarity for the given legion.
    function genAndRarityForLegion(
        uint256 _tokenId
    ) external view returns (LegionGeneration, LegionRarity);
}

// As this will likely change in the future, this should not be used to store state, but rather
// as parameters and return values from functions.
struct LegionMetadata {
    LegionGeneration legionGeneration;
    LegionClass legionClass;
    LegionRarity legionRarity;
    uint8 questLevel;
    uint8 craftLevel;
    uint8[6] constellationRanks;
    uint256 oldId;
}

enum Constellation {
    FIRE,
    EARTH,
    WIND,
    WATER,
    LIGHT,
    DARK
}

enum LegionRarity {
    LEGENDARY,
    RARE,
    SPECIAL,
    UNCOMMON,
    COMMON,
    RECRUIT
}

enum LegionClass {
    RECRUIT,
    SIEGE,
    FIGHTER,
    ASSASSIN,
    RANGED,
    SPELLCASTER,
    RIVERMAN,
    NUMERAIRE,
    ALL_CLASS,
    ORIGIN
}

enum LegionGeneration {
    GENESIS,
    AUXILIARY,
    RECRUIT
}

