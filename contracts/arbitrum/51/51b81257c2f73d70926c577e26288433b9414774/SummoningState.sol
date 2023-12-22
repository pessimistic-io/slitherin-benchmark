//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";
import "./IERC1155Upgradeable.sol";

import "./IRandomizer.sol";
import "./ISummoning.sol";
import "./AdminableUpgradeable.sol";
import "./ILegion.sol";
import "./ILegionMetadataStore.sol";
import "./IStarlightTemple.sol";
import "./ITreasury.sol";
import "./IConsumable.sol";
import "./IMagic.sol";
import "./ILP.sol";
import "./ICrafting.sol";

abstract contract SummoningState is Initializable, ISummoning, ERC721HolderUpgradeable, ERC1155HolderUpgradeable, AdminableUpgradeable {

    event SummoningStarted(address indexed _user, uint256 indexed _tokenId, uint256 indexed _requestId, uint256 _finishTime);
    event NoSummoningToFinish(address indexed _user);
    event SummoningFinished(address indexed _user, uint256 indexed _returnedId, uint256 indexed _newTokenId, uint256 _newTokenSummoningCooldown);

    IRandomizer public randomizer;
    ILegion public legion;
    ILegionMetadataStore public legionMetadataStore;
    IMagic public magic;
    ILP public lp;
    ITreasury public treasury;
    IConsumable public consumable;

    mapping(uint256 => uint32) public tokenIdToSummonCount;
    uint256 public summoningDuration;

    mapping(LegionGeneration => uint32) public generationToMaxSummons;

    // For a given rarity (gen 0 Special) and generation, these are the odds each rarity can be summoned. Out of 100000
    mapping(LegionRarity => mapping(LegionGeneration => mapping(LegionRarity => uint256))) public rarityToGenerationToOddsPerRarity;

    // The name of the variable says LP, but in reality, this is Balancer Crystals.
    mapping(LegionGeneration => SummoningStep[]) public generationToLPRequiredSteps;

    // Chance is out 100,000
    uint256 public chanceAzuriteDustDrop;

    mapping(address => EnumerableSetUpgradeable.UintSet) internal userToSummoningsInProgress;

    mapping(uint256 => uint256) public tokenIdToSummonStartTime;
    // Token ID -> Random number request ID.
    mapping(uint256 => uint256) public tokenIdToRequestId;

    // The name of the variable says LP, but in reality, this is Balancer Crystals.
    mapping(uint256 => uint256) public tokenIdToLPStaked;

    mapping(uint256 => uint256) public tokenIdToCrystalIdUsed;

    // Tracks when a legion was created via summoning. There is an extra cooldown
    // for summoned legions to avoid summoning themselves.
    mapping(uint256 => uint256) public tokenIdToCreatedTime;

    EnumerableSetUpgradeable.UintSet internal crystalIds;
    // Crystal Id => the amount common is reduced, the amount uncommon is increased, and
    // the amount rare is increased. Odds are in terms of 100000
    mapping(uint256 => uint256[3]) public crystalIdToChangedOdds;

    uint256 public summoningFatigueCooldown;

    uint256 public azuriteDustId;

    mapping(LegionGeneration => uint256) public generationToMagicCost;

    bool public isSummoningPaused;

    // Out of 100,000. Can be higher or lower than that value.
    uint256 public successSensitivity;

    uint256 public summoningDurationIfFailed;

    mapping(uint256 => uint256) public tokenIdToSuccessRate;
    mapping(uint256 => uint256) public tokenIdToMagicAmount;
    mapping(uint256 => uint256) public crystalIdToTimeReduction;

    ICrafting public crafting;
    IERC1155Upgradeable public balancerCrystal;
    uint256 public balancerCrystalId;

    function __SummoningState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        summoningDuration = 10 days;
        chanceAzuriteDustDrop = 10;
        generationToMaxSummons[LegionGeneration.AUXILIARY] = 1;
        generationToMaxSummons[LegionGeneration.GENESIS] = uint32(2**32 - 1);

        // Input Common
        rarityToGenerationToOddsPerRarity[LegionRarity.COMMON][LegionGeneration.GENESIS][LegionRarity.COMMON] = 90000;
        rarityToGenerationToOddsPerRarity[LegionRarity.COMMON][LegionGeneration.GENESIS][LegionRarity.UNCOMMON] = 9000;
        rarityToGenerationToOddsPerRarity[LegionRarity.COMMON][LegionGeneration.GENESIS][LegionRarity.RARE] = 1000;

        rarityToGenerationToOddsPerRarity[LegionRarity.COMMON][LegionGeneration.AUXILIARY][LegionRarity.COMMON] = 100000;
        rarityToGenerationToOddsPerRarity[LegionRarity.COMMON][LegionGeneration.AUXILIARY][LegionRarity.UNCOMMON] = 0;
        rarityToGenerationToOddsPerRarity[LegionRarity.COMMON][LegionGeneration.AUXILIARY][LegionRarity.RARE] = 0;

        // Input Uncommon
        rarityToGenerationToOddsPerRarity[LegionRarity.UNCOMMON][LegionGeneration.GENESIS][LegionRarity.COMMON] = 80000;
        rarityToGenerationToOddsPerRarity[LegionRarity.UNCOMMON][LegionGeneration.GENESIS][LegionRarity.UNCOMMON] = 15000;
        rarityToGenerationToOddsPerRarity[LegionRarity.UNCOMMON][LegionGeneration.GENESIS][LegionRarity.RARE] = 5000;

        rarityToGenerationToOddsPerRarity[LegionRarity.UNCOMMON][LegionGeneration.AUXILIARY][LegionRarity.COMMON] = 95000;
        rarityToGenerationToOddsPerRarity[LegionRarity.UNCOMMON][LegionGeneration.AUXILIARY][LegionRarity.UNCOMMON] = 5000;
        rarityToGenerationToOddsPerRarity[LegionRarity.UNCOMMON][LegionGeneration.AUXILIARY][LegionRarity.RARE] = 0;

        // Input Rare
        rarityToGenerationToOddsPerRarity[LegionRarity.RARE][LegionGeneration.GENESIS][LegionRarity.COMMON] = 75000;
        rarityToGenerationToOddsPerRarity[LegionRarity.RARE][LegionGeneration.GENESIS][LegionRarity.UNCOMMON] = 18000;
        rarityToGenerationToOddsPerRarity[LegionRarity.RARE][LegionGeneration.GENESIS][LegionRarity.RARE] = 7000;

        rarityToGenerationToOddsPerRarity[LegionRarity.RARE][LegionGeneration.AUXILIARY][LegionRarity.COMMON] = 90000;
        rarityToGenerationToOddsPerRarity[LegionRarity.RARE][LegionGeneration.AUXILIARY][LegionRarity.UNCOMMON] = 9000;
        rarityToGenerationToOddsPerRarity[LegionRarity.RARE][LegionGeneration.AUXILIARY][LegionRarity.RARE] = 1000;

        // Input Special
        rarityToGenerationToOddsPerRarity[LegionRarity.SPECIAL][LegionGeneration.GENESIS][LegionRarity.COMMON] = 85000;
        rarityToGenerationToOddsPerRarity[LegionRarity.SPECIAL][LegionGeneration.GENESIS][LegionRarity.UNCOMMON] = 12000;
        rarityToGenerationToOddsPerRarity[LegionRarity.SPECIAL][LegionGeneration.GENESIS][LegionRarity.RARE] = 3000;

        // Input Legendary
        rarityToGenerationToOddsPerRarity[LegionRarity.LEGENDARY][LegionGeneration.GENESIS][LegionRarity.COMMON] = 70000;
        rarityToGenerationToOddsPerRarity[LegionRarity.LEGENDARY][LegionGeneration.GENESIS][LegionRarity.UNCOMMON] = 20000;
        rarityToGenerationToOddsPerRarity[LegionRarity.LEGENDARY][LegionGeneration.GENESIS][LegionRarity.RARE] = 10000;

        // Auxiliary never costs LP, but has a max summons of 1.
        generationToLPRequiredSteps[LegionGeneration.AUXILIARY].push(SummoningStep(0, 0, uint32(2**32 - 1)));

        generationToLPRequiredSteps[LegionGeneration.GENESIS].push(SummoningStep(0, 0, 5));
        generationToLPRequiredSteps[LegionGeneration.GENESIS].push(SummoningStep(10 ether, 6, 10));
        generationToLPRequiredSteps[LegionGeneration.GENESIS].push(SummoningStep(30 ether, 11, 15));
        generationToLPRequiredSteps[LegionGeneration.GENESIS].push(SummoningStep(50 ether, 16, uint32(2**32 - 1)));

        summoningFatigueCooldown = 7 days;

        generationToMagicCost[LegionGeneration.GENESIS] = 300 ether;
        generationToMagicCost[LegionGeneration.AUXILIARY] = 500 ether;

        successSensitivity = 100000;
        summoningDurationIfFailed = 2 days;

        azuriteDustId = 11;

        crystalIdToTimeReduction[1] = 43200;
        crystalIdToTimeReduction[2] = 129600;
        crystalIdToTimeReduction[3] = 259200;

        crystalIdToChangedOdds[1] = [6000, 4000, 2000];
        crystalIdToChangedOdds[2] = [10000, 6000, 4000];
        crystalIdToChangedOdds[3] = [14000, 8000, 6000];
    }
}

struct SummoningStep {
    uint256 value;
    uint32 minSummons;
    uint32 maxSummons;
}
