//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IToadzMetadata.sol";
import "./AdminableUpgradeable.sol";
import "./ToadTraitConstants.sol";

abstract contract ToadzMetadataState is Initializable, IToadzMetadata, AdminableUpgradeable {

    event ToadzMetadataChanged(uint256 indexed _tokenId, ToadTraitStrings _traits);
    event HasPurchasedBlueprintChanged(uint256 indexed _tokenId, bool _hasPurchasedBlueprint);

    mapping(uint256 => ToadTraits) public tokenIdToTraits;

    mapping(ToadRarity => string) public rarityToString;
    mapping(ToadBackground => string) public backgroundToString;
    mapping(ToadMushroom => string) public mushroomToString;
    mapping(ToadSkin => string) public skinToString;
    mapping(ToadClothes => string) public clothesToString;
    mapping(ToadMouth => string) public mouthToString;
    mapping(ToadEyes => string) public eyesToString;
    mapping(ToadItem => string) public itemToString;
    mapping(ToadHead => string) public headToString;
    mapping(ToadAccessory => string) public accessoryToString;

    mapping(ToadBackground => string) public backgroundToPNG;
    mapping(ToadMushroom => string) public mushroomToPNG;
    mapping(ToadSkin => string) public skinToPNG;
    mapping(ToadClothes => string) public clothesToPNG;
    mapping(ToadMouth => string) public mouthToPNG;
    mapping(ToadEyes => string) public eyesToPNG;
    mapping(ToadItem => string) public itemToPNG;
    mapping(ToadHead => string) public headToPNG;
    mapping(ToadAccessory => string) public accessoryToPNG;

    mapping(uint256 => SettableToadTraits) public tokenIdToSettableTraits;

    function __ToadzMetadataState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        rarityToString[ToadRarity.COMMON] = ToadTraitConstants.RARITY_COMMON;
        rarityToString[ToadRarity.ONE_OF_ONE] = ToadTraitConstants.RARITY_1_OF_1;
    }
}

// For toad metadata that may be set post mint.
//
struct SettableToadTraits {
    bool hasPurchasedBlueprint;
    uint248 emptySpace;
}
