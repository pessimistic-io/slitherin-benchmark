//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./IRandomizer.sol";
import "./AdminableUpgradeable.sol";
import "./IMiniCrafting.sol";
import "./ITreasure.sol";
import "./IMagic.sol";
import "./ILegion.sol";
import "./ITreasury.sol";
import "./IConsumable.sol";
import "./ITreasureMetadataStore.sol";
import "./ILegionMetadataStore.sol";
import "./ITreasureFragment.sol";
import "./ICrafting.sol";
import "./IRecruitLevel.sol";

abstract contract MiniCraftingState is Initializable, IMiniCrafting, AdminableUpgradeable {

    event RecruitTierInfoSet(uint8 tier, bool canRecruitCraft, uint16 prismShardsRequired, uint32 expGained, uint16 minRecruitLevel, uint8 fragmentsRequired);

    event CraftingFinished(address _user, uint256 _legionId, uint8 _tier, uint8 _cpGained, uint256 _treasureId);

    ICrafting public crafting;
    ILegion public legion;
    ILegionMetadataStore public legionMetadataStore;
    ITreasure public treasure;
    ITreasureMetadataStore public treasureMetadataStore;
    ITreasureFragment public treasureFragment;
    IMagic public magic;
    IConsumable public consumable;
    ITreasury public treasury;

    uint256 public prismShardId;

    mapping(uint8 => FragmentTierInfo) public tierToTierInfo;
    mapping(uint256 => FragmentInfo) public fragmentIdToInfo;

    mapping(uint8 => RecruitTierInfo) public tierToRecruitTierInfo;

    IRecruitLevel public recruitLevel;

    function __MiniCraftingState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        prismShardId = 9;

        tierToTierInfo[1] = FragmentTierInfo(12 ether, 24, 12, 12, 1);
        tierToTierInfo[2] = FragmentTierInfo(8 ether, 16, 12, 8, 1);
        tierToTierInfo[3] = FragmentTierInfo(4 ether, 8, 12, 4, 1);
        tierToTierInfo[4] = FragmentTierInfo(2 ether, 4, 12, 2, 1);
        tierToTierInfo[5] = FragmentTierInfo(1 ether, 2, 12, 1, 1);

        fragmentIdToInfo[1].tier = 1;
        // Only can craft an alchemy tier 1. No Grin :(
        fragmentIdToInfo[1].categories.push(TreasureCategory.ALCHEMY);
        fragmentIdToInfo[2].tier = 2;
        fragmentIdToInfo[2].categories.push(TreasureCategory.ALCHEMY);
        fragmentIdToInfo[2].categories.push(TreasureCategory.ARCANA);
        fragmentIdToInfo[3].tier = 3;
        fragmentIdToInfo[3].categories.push(TreasureCategory.ALCHEMY);
        fragmentIdToInfo[3].categories.push(TreasureCategory.ARCANA);
        fragmentIdToInfo[4].tier = 4;
        fragmentIdToInfo[4].categories.push(TreasureCategory.ALCHEMY);
        fragmentIdToInfo[4].categories.push(TreasureCategory.ARCANA);
        fragmentIdToInfo[5].tier = 5;
        fragmentIdToInfo[5].categories.push(TreasureCategory.ALCHEMY);
        fragmentIdToInfo[5].categories.push(TreasureCategory.ARCANA);
        fragmentIdToInfo[6].tier = 1;
        fragmentIdToInfo[6].categories.push(TreasureCategory.BREWING);
        fragmentIdToInfo[6].categories.push(TreasureCategory.ENCHANTER);
        fragmentIdToInfo[7].tier = 2;
        fragmentIdToInfo[7].categories.push(TreasureCategory.BREWING);
        fragmentIdToInfo[7].categories.push(TreasureCategory.ENCHANTER);
        fragmentIdToInfo[8].tier = 3;
        fragmentIdToInfo[8].categories.push(TreasureCategory.BREWING);
        fragmentIdToInfo[8].categories.push(TreasureCategory.ENCHANTER);
        fragmentIdToInfo[9].tier = 4;
        fragmentIdToInfo[9].categories.push(TreasureCategory.BREWING);
        fragmentIdToInfo[9].categories.push(TreasureCategory.ENCHANTER);
        fragmentIdToInfo[10].tier = 5;
        fragmentIdToInfo[10].categories.push(TreasureCategory.BREWING);
        fragmentIdToInfo[10].categories.push(TreasureCategory.ENCHANTER);
        fragmentIdToInfo[11].tier = 1;
        // Only can craft a smithing tier 1. No honeycomb :(
        fragmentIdToInfo[11].categories.push(TreasureCategory.SMITHING);
        fragmentIdToInfo[12].tier = 2;
        fragmentIdToInfo[12].categories.push(TreasureCategory.LEATHERWORKING);
        fragmentIdToInfo[12].categories.push(TreasureCategory.SMITHING);
        fragmentIdToInfo[13].tier = 3;
        fragmentIdToInfo[13].categories.push(TreasureCategory.LEATHERWORKING);
        fragmentIdToInfo[13].categories.push(TreasureCategory.SMITHING);
        fragmentIdToInfo[14].tier = 4;
        fragmentIdToInfo[14].categories.push(TreasureCategory.LEATHERWORKING);
        fragmentIdToInfo[14].categories.push(TreasureCategory.SMITHING);
        fragmentIdToInfo[15].tier = 5;
        fragmentIdToInfo[15].categories.push(TreasureCategory.LEATHERWORKING);
        fragmentIdToInfo[15].categories.push(TreasureCategory.SMITHING);
    }
}

struct FragmentTierInfo {
    uint128 magicCost;
    uint16 prismShardsRequired;
    uint8 fragmentsRequired;
    uint8 craftingCPGained;
    uint8 minimumCraftingLevel;
}

struct RecruitTierInfo {
    bool canRecruitCraft;
    uint16 prismShardsRequired;
    uint32 expGained;
    uint16 minRecruitLevel;
    uint8 fragmentsRequired;
    uint176 emptySpace;
}

struct FragmentInfo {
    uint8 tier;
    TreasureCategory[] categories;
}
