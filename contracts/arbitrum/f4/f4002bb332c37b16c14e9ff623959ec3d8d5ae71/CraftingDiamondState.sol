//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./IRandomizer.sol";
import "./ICrafting.sol";
import "./AdminableUpgradeable.sol";
import "./ITreasure.sol";
import "./IMagic.sol";
import "./ILegion.sol";
import "./ITreasury.sol";
import "./IConsumable.sol";
import "./ITreasureMetadataStore.sol";
import "./ILegionMetadataStore.sol";
import "./ICorruption.sol";

abstract contract CraftingDiamondState is Initializable, ERC721HolderUpgradeable, ERC1155HolderUpgradeable, AdminableUpgradeable {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    event CraftingStarted(address indexed _owner, uint256 indexed _tokenId, uint256 indexed _requestId, uint256 _finishTime, uint256[] _treasureIds, uint8[] _treasureAmounts, RecipeDifficulty _difficulty);
    event CraftingRevealed(address indexed _owner, uint256 indexed _tokenId, CraftingOutcome _outcome);
    event CraftingFinished(address indexed _owner, uint256 indexed _tokenId);

    event CPGained(uint256 _tokenId, uint8 _craftLevel, uint256 _cpFinal);

    uint256 constant SMALL_PRISM_ID = 1;
    uint256 constant MEDIUM_PRISM_ID = 2;
    uint256 constant EOS_ID = 8;
    uint256 constant PRISM_SHARDS_ID = 9;

    IRandomizer internal randomizer;
    ITreasure internal treasure;
    ILegion internal legion;
    ITreasureMetadataStore internal treasureMetadataStore;
    ILegionMetadataStore internal legionMetadataStore;
    IMagic internal magic;
    ITreasury internal treasury;
    IConsumable internal consumable;

    mapping(RecipeDifficulty => uint256) public difficultyToRecipeLength;
    mapping(RecipeDifficulty => uint256) public difficultyToSuccessRate;
    mapping(RecipeDifficulty => uint8[5]) public difficultyToAmountPerTier;
    mapping(RecipeDifficulty => uint8) public difficultyToLevelUnlocked;

    // Reward state
    mapping(RecipeDifficulty => CraftingReward[]) public difficultyToRewards;

    uint8 public maxCraftingLevel;
    uint256[] public levelToCPNeeded;
    // DEPRECATED
    uint256[] public levelToCPGainedPerRecipe;

    mapping(address => EnumerableSetUpgradeable.UintSet) internal userToLegionsInProgress;

    mapping(uint256 => uint256) public tokenIdToCP;
    mapping(uint256 => uint256) public tokenIdToCraftingStartTime;
    mapping(uint256 => uint256) public tokenIdToRequestId;
    mapping(uint256 => uint256) public tokenIdToMagicPaid;
    mapping(uint256 => RecipeDifficulty) public tokenIdToRecipeDifficulty;
    mapping(uint256 => StakedTreasure[]) public tokenIdToStakedTreasure;

    uint256 public craftingFee;
    uint8 public percentReturnedOnFailure;

    mapping(RecipeDifficulty => mapping(LegionGeneration => CraftingReward[])) public difficultyToGenerationToRewards;
    mapping(RecipeDifficulty => uint256) public difficultyToCPGained;

    ICorruption internal corruption;

    function __CraftingDiamondState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        difficultyToRecipeLength[RecipeDifficulty.EASY] = 8 hours;
        difficultyToRecipeLength[RecipeDifficulty.MEDIUM] = 12 hours;
        difficultyToRecipeLength[RecipeDifficulty.HARD] = 16 hours;
        difficultyToRecipeLength[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = 2 days;
        difficultyToRecipeLength[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = 2 days;

        difficultyToSuccessRate[RecipeDifficulty.EASY] = 100000;
        difficultyToSuccessRate[RecipeDifficulty.MEDIUM] = 100000;
        difficultyToSuccessRate[RecipeDifficulty.HARD] = 100000;
        difficultyToSuccessRate[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = 100000;
        difficultyToSuccessRate[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = 100000;

        difficultyToLevelUnlocked[RecipeDifficulty.EASY] = 1;
        difficultyToLevelUnlocked[RecipeDifficulty.MEDIUM] = 3;
        difficultyToLevelUnlocked[RecipeDifficulty.HARD] = 5;
        difficultyToLevelUnlocked[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = 1;
        difficultyToLevelUnlocked[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = 1;

        difficultyToAmountPerTier[RecipeDifficulty.EASY] = [0, 0, 1, 2, 4];
        difficultyToAmountPerTier[RecipeDifficulty.MEDIUM] = [1, 1, 2, 2, 5];
        difficultyToAmountPerTier[RecipeDifficulty.HARD] = [0, 1, 1, 3, 4];
        difficultyToAmountPerTier[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = [0, 0, 0, 0, 0];
        difficultyToAmountPerTier[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = [0, 0, 0, 0, 0];

        difficultyToRewards[RecipeDifficulty.EASY].push(CraftingReward(1, 1, 75000));
        difficultyToRewards[RecipeDifficulty.EASY].push(CraftingReward(2, 1, 15000));
        difficultyToRewards[RecipeDifficulty.EASY].push(CraftingReward(3, 1, 10000));
        difficultyToRewards[RecipeDifficulty.MEDIUM].push(CraftingReward(7, 1, 99990));
        difficultyToRewards[RecipeDifficulty.MEDIUM].push(CraftingReward(7, 2, 10));
        difficultyToRewards[RecipeDifficulty.HARD].push(CraftingReward(4, 1, 75000));
        difficultyToRewards[RecipeDifficulty.HARD].push(CraftingReward(5, 1, 15000));
        difficultyToRewards[RecipeDifficulty.HARD].push(CraftingReward(6, 1, 10000));
        difficultyToRewards[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM].push(CraftingReward(2, 1, 100000));
        difficultyToRewards[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE].push(CraftingReward(3, 1, 100000));

        maxCraftingLevel = 6;

        levelToCPNeeded.push(0);
        levelToCPNeeded.push(140);
        levelToCPNeeded.push(160);
        levelToCPNeeded.push(160);
        levelToCPNeeded.push(160);
        levelToCPNeeded.push(480);

        difficultyToCPGained[RecipeDifficulty.EASY] = 10;
        difficultyToCPGained[RecipeDifficulty.MEDIUM] = 20;
        difficultyToCPGained[RecipeDifficulty.HARD] = 40;
        difficultyToCPGained[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = 0;
        difficultyToCPGained[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = 0;

        percentReturnedOnFailure = 90;

        craftingFee = 5 ether;
    }
}

struct StartCraftingParams {
    uint256 legionId;
    RecipeDifficulty difficulty;
    uint256[] treasureIds;
    uint8[] treasureAmounts;
}

// Do not change, stored in state.
struct CraftingReward {
    uint256 consumableId;
    uint8 amount;
    uint32 odds;
}

// Do not change, stored in state.
struct StakedTreasure {
    uint8 amount;
    uint256 treasureId;
}

// Safe to change, as only in event not in state.
struct CraftingOutcome {
    bool wasSuccessful;
    uint256 magicReturned;
    uint256 rewardId;
    uint256[] brokenTreasureIds;
    uint256[] brokenAmounts;
    uint8 rewardAmount;
}

enum RecipeDifficulty {
    EASY,
    MEDIUM,
    HARD,
    PRISM_UPGRADE_SMALL_TO_MEDIUM,
    PRISM_UPGRADE_MEDIUM_TO_LARGE
}
