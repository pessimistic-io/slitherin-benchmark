// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IToadHousezMetadata {
    function tokenURI(uint256 _tokenId) external view returns(string memory);

    function setMetadataForHouse(uint256 _tokenId, ToadHouseTraits calldata _traits) external;
}

// Immutable Traits.
// Do not change.
struct ToadHouseTraits {
    HouseRarity rarity;
    HouseVariation variation;
    HouseBackground background;
    HouseBase base;
    WoodType main;
    WoodType left;
    WoodType right;
    WoodType door;
    WoodType mushroom;
}

// The string represenation of the various traits.
// variation is still a uint as there is no string representation.
//
struct ToadHouseTraitStrings {
    string rarity;
    uint8 variation;
    string background;
    string base;
    string main;
    string left;
    string right;
    string door;
    string mushroom;
}

enum HouseRarity {
    COMMON,
    ONE_OF_ONE
}

enum HouseBackground {
    BLUE
}

enum HouseBase {
    GRASS
}

enum WoodType {
    PINE,
    OAK,
    REDWOOD,
    BUFO_WOOD,
    WITCH_WOOD,
    TOAD_WOOD,
    GOLD_WOOD,
    SAKURA_WOOD
}

enum HouseVariation {
    VARIATION_1,
    VARIATION_2,
    VARIATION_3
}

string constant RARITY = "Rarity";
string constant BACKGROUND = "Background";
string constant BASE = "Base";
string constant WOOD_TYPE = "Wood Type";
string constant VARIATION = "Variation";
string constant MAIN = "Main";
string constant LEFT = "Left";
string constant RIGHT = "Right";
string constant DOOR = "Door";
string constant MUSHROOM = "Mushroom";
