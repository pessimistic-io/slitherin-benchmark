//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IToadHousezMetadata.sol";
import "./AdminableUpgradeable.sol";

abstract contract ToadHousezMetadataState is Initializable, IToadHousezMetadata, AdminableUpgradeable {

    event ToadHousezMetadataChanged(uint256 indexed _tokenId, ToadHouseTraitStrings _traits);

    mapping(uint256 => ToadHouseTraits) public tokenIdToTraits;

    mapping(HouseRarity => string) public rarityToString;
    mapping(HouseBackground => string) public backgroundToString;
    // Deprecated
    mapping(uint8 => string) public baseToString;
    mapping(WoodType => string) public woodTypeToString;

    mapping(HouseBackground => string) public backgroundToPNG;
    // Deprecated
    mapping(uint8 => string) public baseToPNG;
    mapping(WoodType => mapping(HouseVariation => string)) public mainToVariationToPNG;
    mapping(WoodType => mapping(HouseVariation => string)) public leftToVariationToPNG;
    mapping(WoodType => mapping(HouseVariation => string)) public rightToVariationToPNG;
    mapping(WoodType => mapping(HouseVariation => string)) public doorToVariationToPNG;
    mapping(WoodType => mapping(HouseVariation => string)) public mushroomToVariationToPNG;
    mapping(HouseSmoke => string) public smokeToString;
    mapping(HouseSmoke => mapping(HouseVariation => string)) public smokeToVariationToPNG;

    function __ToadHousezMetadataState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        rarityToString[HouseRarity.COMMON] = "Common";
        rarityToString[HouseRarity.ONE_OF_ONE] = "1 of 1";
    }
}
