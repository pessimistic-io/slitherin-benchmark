// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ToadTraitConstants.sol";

interface IToadzMetadata {
    function tokenURI(uint256 _tokenId) external view returns(string memory);

    function setMetadataForToad(uint256 _tokenId, ToadTraits calldata _traits) external;

    function setHasPurchasedBlueprint(uint256 _tokenId) external;

    function hasPurchasedBlueprint(uint256 _tokenId) external view returns(bool);
}

// Immutable Traits.
// Do not change.
struct ToadTraits {
    ToadRarity rarity;
    ToadBackground background;
    ToadMushroom mushroom;
    ToadSkin skin;
    ToadClothes clothes;
    ToadMouth mouth;
    ToadEyes eyes;
    ToadItem item;
    ToadHead head;
    ToadAccessory accessory;
}

struct ToadTraitStrings {
    string rarity;
    string background;
    string mushroom;
    string skin;
    string clothes;
    string mouth;
    string eyes;
    string item;
    string head;
    string accessory;
}
