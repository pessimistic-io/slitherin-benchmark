//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./IRandomizer.sol";
import "./IQuesting.sol";
import "./AdminableUpgradeable.sol";
import "./ITreasure.sol";
import "./ILP.sol";
import "./ILegion.sol";
import "./IConsumable.sol";
import "./ITreasureMetadataStore.sol";
import "./ILegionMetadataStore.sol";
import "./ITreasury.sol";

abstract contract QuestingState is Initializable, IQuesting, ERC721HolderUpgradeable, ERC1155HolderUpgradeable, AdminableUpgradeable {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    event QuestStarted(address indexed _owner, uint256 indexed _tokenId, uint256 indexed _requestId, uint256 _finishTime, QuestDifficulty _difficulty);
    event QuestRevealed(address indexed _owner, uint256 indexed _tokenId, QuestReward _reward);
    event QuestFinished(address indexed _owner, uint256 indexed _tokenId);

    IRandomizer public randomizer;
    ITreasure public treasure;
    ILegion public legion;
    IConsumable public consumable;
    ITreasureMetadataStore public treasureMetadataStore;
    ILegionMetadataStore public legionMetadataStore;
    ILP public lp;

    mapping(QuestDifficulty => uint256) public difficultyToQuestLength;
    mapping(QuestDifficulty => uint8) public difficultyToLevelUnlocked;
    mapping(QuestDifficulty => uint8) public difficultyToStarlightAmount;
    mapping(QuestDifficulty => uint8) public difficultyToShardAmount;
    // Ordered from tier 1 (index 0) -> tier 5 (index 4)
    mapping(QuestDifficulty => uint256[5]) public difficultyToTierOdds;
    mapping(QuestDifficulty => uint256) public difficultyToLPNeeded;

    uint8 public maxQuestLevel;
    uint256[] public levelToQPNeeded;
    uint256[] public levelToQPGainedPerQuest;

    mapping(address => EnumerableSetUpgradeable.UintSet) internal userToQuestsInProgress;

    mapping(uint256 => uint256) public tokenIdToQP;
    mapping(uint256 => uint256) public tokenIdToQuestStartTime;
    mapping(uint256 => uint256) public tokenIdToRequestId;
    mapping(uint256 => QuestDifficulty) public tokenIdToQuestDifficulty;
    mapping(uint256 => uint256) public tokenIdToLPStaked;
    mapping(uint256 => uint256) public tokenIdToNumberLoops;

    uint256 public treasureDropOdds;
    uint256 public universalLockDropOdds;
    uint256 public starlightId;
    uint256 public shardId;
    uint256 public universalLockId;

    EnumerableSetUpgradeable.UintSet internal availableAutoQuestLoops;

    uint8 public recruitNumberOfStarlight;
    uint8 public recruitNumberOfCrystalShards;
    // Out of 100,000
    uint256 public recruitCrystalShardsOdds;
    uint256 public recruitUniversalLockOdds;

    ITreasury public treasury;

    function __QuestingState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        difficultyToQuestLength[QuestDifficulty.EASY] = 8 hours;
        difficultyToQuestLength[QuestDifficulty.MEDIUM] = 12 hours;
        difficultyToQuestLength[QuestDifficulty.HARD] = 16 hours;

        difficultyToLevelUnlocked[QuestDifficulty.EASY] = 1;
        difficultyToLevelUnlocked[QuestDifficulty.MEDIUM] = 3;
        difficultyToLevelUnlocked[QuestDifficulty.HARD] = 5;

        maxQuestLevel = 6;

        // Level starts at 1
        levelToQPNeeded.push(0);
        levelToQPNeeded.push(100);
        levelToQPNeeded.push(200);
        levelToQPNeeded.push(500);
        levelToQPNeeded.push(1000);
        levelToQPNeeded.push(2000);

        // Level starts at 1
        levelToQPGainedPerQuest.push(0);
        levelToQPGainedPerQuest.push(10);
        levelToQPGainedPerQuest.push(10);
        levelToQPGainedPerQuest.push(20);
        levelToQPGainedPerQuest.push(20);
        levelToQPGainedPerQuest.push(40);

        treasureDropOdds = 20000;
        universalLockDropOdds = 10;

        difficultyToTierOdds[QuestDifficulty.EASY] = [0, 2500, 5000, 15000, 77500];
        difficultyToTierOdds[QuestDifficulty.MEDIUM] = [1500, 5000, 7000, 17000, 69500];
        difficultyToTierOdds[QuestDifficulty.HARD] = [2500, 9000, 8000, 22000, 58500];

        availableAutoQuestLoops.add(3);
        availableAutoQuestLoops.add(9);
        availableAutoQuestLoops.add(15);

        difficultyToLPNeeded[QuestDifficulty.EASY] = 5 ether;
        difficultyToLPNeeded[QuestDifficulty.MEDIUM] = 10 ether;
        difficultyToLPNeeded[QuestDifficulty.HARD] = 15 ether;

        difficultyToStarlightAmount[QuestDifficulty.EASY] = 3;
        difficultyToStarlightAmount[QuestDifficulty.MEDIUM] = 4;
        difficultyToStarlightAmount[QuestDifficulty.HARD] = 5;

        difficultyToShardAmount[QuestDifficulty.EASY] = 3;
        difficultyToShardAmount[QuestDifficulty.MEDIUM] = 4;
        difficultyToShardAmount[QuestDifficulty.HARD] = 5;

        recruitNumberOfStarlight = 1;
        recruitNumberOfCrystalShards = 1;
        recruitCrystalShardsOdds = 50000;
        recruitUniversalLockOdds = 1;
    }
}

enum QuestDifficulty {
    EASY,
    MEDIUM,
    HARD
}

// This is okay to modify, as it used in an event rather than in state.
struct QuestReward {
    uint8 starlightAmount;
    uint8 crystalShardAmount;
    uint8 universalLockAmount;
    // The ID of the treasure received. Will be 0 if no treasure received.
    uint256 treasureId;
}
