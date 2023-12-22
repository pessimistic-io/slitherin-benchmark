//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ICryptsCharacterHandler.sol";
import "./ICorruptionCryptsRewards.sol";
import "./AdminableUpgradeable.sol";
import "./ICorruption.sol";
import "./ILegionMetadataStore.sol";
import "./ILegion.sol";
import "./ICorruptionCrypts.sol";
import "./IConsumable.sol";
import "./IDoomsdayPoints.sol";
import "./EnumerableSet.sol";

abstract contract CorruptionCryptsRewardsState is Initializable, ICorruptionCryptsRewards, AdminableUpgradeable {

    event RoundResetTimeAllowanceSet(uint256 roundResetTimeAllowance);
    event MinimumCraftLevelForAuxCorruptionSet(uint256 craftLevel);
    event MalevolentPrismsPerCraftSet(uint256 malevolentPrisms);
    event LegionPercentOfPoolClaimedChanged(LegionGeneration generation, LegionRarity rarity, uint32 percentOfPool);

    event CharacterCraftedCorruption(address _user, address _collection, uint32 _tokenId, uint32 _roundCraftedFor, uint256 _amountCrafted);

    event HarvesterAgeChanged(address harvester, uint128 timeCreated, uint128 ageDebuff);
    event MinimumAgeForHarvesterDeathChanged(uint256 minimumAgeForHarvesterDeath);
    event AgeDebuffForYoungHarvesterChanged(uint256 ageDebuffForYoungHarvester);

    event MaximumDyingHarvestersChanged(uint256 maximumDyingHarvesters);

    uint256 constant MALEVOLENT_PRISM_ID = 15;

    ICorruption public corruption;
    ILegionMetadataStore public legionMetadataStore;
    ICorruptionCrypts public corruptionCrypts;
    IConsumable public consumable;

    HarvesterCorruptionInfo public harvesterCorruptionInfo;

    uint256 public roundResetTimeAllowance;
    uint256 public minimumCraftLevelForAuxCorruption;
    uint256 public malevolentPrismsPerCraft;

    mapping(LegionGeneration => mapping(LegionRarity => uint24)) public generationToRarityToCorruptionDiversion;
    mapping(LegionGeneration => mapping(LegionRarity => uint32)) public generationToRarityToPercentOfPoolClaimed;
    HarvesterInfo[] public activeHarvesterInfos;

    mapping(uint32 => LegionInfo) public legionIdToInfo;

    mapping(address => mapping(uint32 => CharacterCraftingInfo)) public collectionAddressToTokenIdToCharacterCraftingInfo;
    ILegion public legion;
    IDoomsdayPoints public doomsdayPoints;

    mapping(address => AgeInfo) public harvesterAddressToAgeInfo;
    // The minimum age a harvester must be in order to die. This is caculated
    // based on time of creation and does not include age debuff.
    //
    uint256 public minimumAgeForHarvesterDeath;
    // For a harvester that cannot die due to minimumAgeForHarvesterDeath, this is how much is added to the ageDebuff when the doomsday points
    // reach their max value.
    //
    uint256 public ageDebuffForYoungHarvester;
    // The maximum number of harvesters that can be dying at one point.
    //
    uint256 public maximumDyingHarvesters;

    EnumerableSet.AddressSet dyingHarvestersSet;

    function __CorruptionCryptsRewardsState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();

        roundResetTimeAllowance = 30 minutes;
        emit RoundResetTimeAllowanceSet(roundResetTimeAllowance);

        minimumCraftLevelForAuxCorruption = 3;
        emit MinimumCraftLevelForAuxCorruptionSet(minimumCraftLevelForAuxCorruption);

        malevolentPrismsPerCraft = 1;
        emit MalevolentPrismsPerCraftSet(malevolentPrismsPerCraft);

        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.LEGENDARY] = 600;
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.RARE] = 400;
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.UNCOMMON] = 200;
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.SPECIAL] = 150;
        generationToRarityToCorruptionDiversion[LegionGeneration.GENESIS][LegionRarity.COMMON] = 100;
        generationToRarityToCorruptionDiversion[LegionGeneration.AUXILIARY][LegionRarity.RARE] = 10;
        generationToRarityToCorruptionDiversion[LegionGeneration.AUXILIARY][LegionRarity.UNCOMMON] = 5;

        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.LEGENDARY, 1400);
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.RARE, 1000);
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.UNCOMMON, 600);
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.SPECIAL, 500);
        _setLegionPercentOfPoolClaimed(LegionGeneration.GENESIS, LegionRarity.COMMON, 400);
        _setLegionPercentOfPoolClaimed(LegionGeneration.AUXILIARY, LegionRarity.RARE, 220);
        _setLegionPercentOfPoolClaimed(LegionGeneration.AUXILIARY, LegionRarity.UNCOMMON, 210);
        _setLegionPercentOfPoolClaimed(LegionGeneration.AUXILIARY, LegionRarity.COMMON, 200);
    }

    function _setLegionPercentOfPoolClaimed(
        LegionGeneration _generation,
        LegionRarity _rarity,
        uint32 _percent)
    private
    {
        generationToRarityToPercentOfPoolClaimed[_generation][_rarity] = _percent;
        emit LegionPercentOfPoolClaimedChanged(_generation, _rarity, _percent);
    }
}

// Not safe to update struct past 1 slot
//
struct HarvesterInfo {
    address harvesterAddress;
    uint96 emptySpace;
}

struct AgeInfo {
    // Slot 1
    // The block.timestamp the harvester was originally created.
    //
    uint128 timeCreated;
    // An additional debuff (in seconds) for this harvester.
    //
    uint128 ageDebuff;
}

// Instead of storing the corruption points in a mapping, we will pack all the points info together into one struct. This will support all 9 potentional harvesters
// and keep balance writes down to 1 storage slot.
struct HarvesterCorruptionInfo {
    uint24 totalCorruptionDiversionPoints;
    uint24 harvester1CorruptionPoints;
    uint24 harvester2CorruptionPoints;
    uint24 harvester3CorruptionPoints;
    uint24 harvester4CorruptionPoints;
    uint24 harvester5CorruptionPoints;
    uint24 harvester6CorruptionPoints;
    uint24 harvester7CorruptionPoints;
    uint24 harvester8CorruptionPoints;
    uint24 harvester9CorruptionPoints;
    uint16 emptySpace;
}

struct LegionInfo {
    uint32 lastRoundCrafted;
}

struct CharacterCraftingInfo {
    uint32 lastRoundCrafted;
}


