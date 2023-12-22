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

abstract contract CraftingState is Initializable, ICrafting, ERC721HolderUpgradeable, ERC1155HolderUpgradeable, AdminableUpgradeable {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    event CraftingStarted(address indexed _owner, uint256 indexed _tokenId, uint256 indexed _requestId, uint256 _finishTime, uint256[] _treasureIds, uint8[] _treasureAmounts);
    event CraftingRevealed(address indexed _owner, uint256 indexed _tokenId, CraftingOutcome _outcome);
    event CraftingFinished(address indexed _owner, uint256 indexed _tokenId);

    IRandomizer public randomizer;
    ITreasure public treasure;
    ILegion public legion;
    ITreasureMetadataStore public treasureMetadataStore;
    ILegionMetadataStore public legionMetadataStore;
    IMagic public magic;
    ITreasury public treasury;
    IConsumable public consumable;

    mapping(RecipeDifficulty => uint256) public difficultyToRecipeLength;
    mapping(RecipeDifficulty => uint256) public difficultyToSuccessRate;
    mapping(RecipeDifficulty => uint8[5]) public difficultyToAmountPerTier;
    mapping(RecipeDifficulty => uint8) public difficultyToLevelUnlocked;

    // Reward state
    mapping(RecipeDifficulty => CraftingReward[]) public difficultyToRewards;

    uint8 public maxCraftingLevel;
    uint256[] public levelToCPNeeded;
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

    function __CraftingState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        difficultyToRecipeLength[RecipeDifficulty.EASY] = 8 hours;
        difficultyToRecipeLength[RecipeDifficulty.MEDIUM] = 12 hours;
        difficultyToRecipeLength[RecipeDifficulty.HARD] = 16 hours;

        difficultyToSuccessRate[RecipeDifficulty.EASY] = 90000;
        difficultyToSuccessRate[RecipeDifficulty.MEDIUM] = 90000;
        difficultyToSuccessRate[RecipeDifficulty.HARD] = 90000;

        difficultyToLevelUnlocked[RecipeDifficulty.EASY] = 1;
        difficultyToLevelUnlocked[RecipeDifficulty.MEDIUM] = 3;
        difficultyToLevelUnlocked[RecipeDifficulty.HARD] = 5;

        difficultyToAmountPerTier[RecipeDifficulty.EASY] = [0, 0, 0, 1, 2];
        difficultyToAmountPerTier[RecipeDifficulty.MEDIUM] = [0, 0, 1, 2, 2];
        difficultyToAmountPerTier[RecipeDifficulty.HARD] = [1, 1, 1, 2, 2];

        maxCraftingLevel = 6;

        levelToCPNeeded.push(0);
        levelToCPNeeded.push(100);
        levelToCPNeeded.push(200);
        levelToCPNeeded.push(400);
        levelToCPNeeded.push(1500);
        levelToCPNeeded.push(2000);

        levelToCPGainedPerRecipe.push(0);
        levelToCPGainedPerRecipe.push(10);
        levelToCPGainedPerRecipe.push(20);
        levelToCPGainedPerRecipe.push(30);
        levelToCPGainedPerRecipe.push(40);
        levelToCPGainedPerRecipe.push(50);

        percentReturnedOnFailure = 90;

        craftingFee = 25 ether;
    }
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
    HARD
}
