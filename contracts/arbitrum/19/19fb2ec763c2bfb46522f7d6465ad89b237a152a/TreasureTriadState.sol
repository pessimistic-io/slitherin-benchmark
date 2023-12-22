//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IAdvancedQuestingDiamond.sol";
import "./ILegionMetadataStore.sol";
import "./ITreasureMetadataStore.sol";
import "./ITreasureTriad.sol";
import "./AdminableUpgradeable.sol";
import "./IRandomizer.sol";

abstract contract TreasureTriadState is Initializable, ITreasureTriad, AdminableUpgradeable {

    event TreasureCardInfoSet(uint256 _treasureId, CardInfo _cardInfo);

    uint8 constant NUMBER_OF_CONTRACT_CARDS = 3;
    uint8 constant NUMBER_OF_CELLS_WITH_AFFINITY = 2;
    uint8 constant MAX_NUMBER_OF_CORRUPTED_CELLS = 2;

    IAdvancedQuestingDiamond public advancedQuesting;
    ITreasureMetadataStore public treasureMetadataStore;

    // Used to check if the given legion class has an afinity for the treasure category (i.e. alchemy, arcana, etc.)
    mapping(LegionClass => mapping(TreasureCategory => bool)) public classToTreasureCategoryToHasAffinity;

    EnumerableSetUpgradeable.UintSet internal treasureIds;
    // Maps the treasure id to the info about the card.
    // Used for both contract and player placed cards.
    mapping(uint256 => CardInfo) public treasureIdToCardInfo;

    // The base rarities for each tier of treasure out of 256.
    uint8[5] public baseTreasureRarityPerTier;

    uint8 public numberOfFlippedCardsToWin;

    IRandomizer public randomizer;

    function __TreasureTriadState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        baseTreasureRarityPerTier = [51, 51, 51, 51, 52];

        numberOfFlippedCardsToWin = 2;

        _setInitialClassToCategory();
    }

    function _setInitialClassToCategory() private {
        classToTreasureCategoryToHasAffinity[LegionClass.SIEGE][TreasureCategory.ALCHEMY] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.SIEGE][TreasureCategory.ENCHANTER] = true;

        classToTreasureCategoryToHasAffinity[LegionClass.FIGHTER][TreasureCategory.SMITHING] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.FIGHTER][TreasureCategory.ENCHANTER] = true;

        classToTreasureCategoryToHasAffinity[LegionClass.ASSASSIN][TreasureCategory.BREWING] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ASSASSIN][TreasureCategory.LEATHERWORKING] = true;

        classToTreasureCategoryToHasAffinity[LegionClass.RANGED][TreasureCategory.ALCHEMY] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.RANGED][TreasureCategory.LEATHERWORKING] = true;

        classToTreasureCategoryToHasAffinity[LegionClass.SPELLCASTER][TreasureCategory.ARCANA] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.SPELLCASTER][TreasureCategory.ENCHANTER] = true;

        classToTreasureCategoryToHasAffinity[LegionClass.RIVERMAN][TreasureCategory.BREWING] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.RIVERMAN][TreasureCategory.ENCHANTER] = true;

        classToTreasureCategoryToHasAffinity[LegionClass.NUMERAIRE][TreasureCategory.ARCANA] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.NUMERAIRE][TreasureCategory.ALCHEMY] = true;

        classToTreasureCategoryToHasAffinity[LegionClass.ALL_CLASS][TreasureCategory.ALCHEMY] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ALL_CLASS][TreasureCategory.ARCANA] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ALL_CLASS][TreasureCategory.BREWING] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ALL_CLASS][TreasureCategory.ENCHANTER] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ALL_CLASS][TreasureCategory.LEATHERWORKING] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ALL_CLASS][TreasureCategory.SMITHING] = true;

        classToTreasureCategoryToHasAffinity[LegionClass.ORIGIN][TreasureCategory.ALCHEMY] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ORIGIN][TreasureCategory.ARCANA] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ORIGIN][TreasureCategory.BREWING] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ORIGIN][TreasureCategory.ENCHANTER] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ORIGIN][TreasureCategory.LEATHERWORKING] = true;
        classToTreasureCategoryToHasAffinity[LegionClass.ORIGIN][TreasureCategory.SMITHING] = true;
    }
}

struct CardInfo {
    // While this is a repeat of the information stored in TreasureMetadataStore, overall it is beneficial
    // to have this information readily available in this contract.
    TreasureCategory category;
    uint8 north;
    uint8 east;
    uint8 south;
    uint8 west;
}
