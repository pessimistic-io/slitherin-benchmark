//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./QuestingContracts.sol";

abstract contract QuestingSettings is Initializable, QuestingContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __QuestingSettings_init() internal initializer {
        QuestingContracts.__QuestingContracts_init();
    }

    function setQuestLengths(
        uint256 _easyLength,
        uint256 _mediumLength,
        uint256 _hardLength)
    external
    onlyAdminOrOwner
    {
        difficultyToQuestLength[QuestDifficulty.EASY] = _easyLength;
        difficultyToQuestLength[QuestDifficulty.MEDIUM] = _mediumLength;
        difficultyToQuestLength[QuestDifficulty.HARD] = _hardLength;
    }

    function setLevelDifficultyUnlocks(
        uint8 _easyLevel,
        uint8 _mediumLevel,
        uint8 _hardLevel)
    external
    onlyAdminOrOwner
    {
        difficultyToLevelUnlocked[QuestDifficulty.EASY] = _easyLevel;
        difficultyToLevelUnlocked[QuestDifficulty.MEDIUM] = _mediumLevel;
        difficultyToLevelUnlocked[QuestDifficulty.HARD] = _hardLevel;
    }

    function setLevelSteps(
        uint8 _maxQuestLevel,
        uint256[] calldata _qpNeededForEachLevel,
        uint256[] calldata _qpGainedAtEachLevel
    )
    external
    onlyAdminOrOwner
    {
        require(_maxQuestLevel > 0, "Bad max level");
        require(_qpNeededForEachLevel.length == _maxQuestLevel - 1, "Not enough QP steps");
        require(_qpGainedAtEachLevel.length == _maxQuestLevel - 1, "Not enough QP gained steps");

        maxQuestLevel = _maxQuestLevel;

        delete levelToQPNeeded;
        delete levelToQPGainedPerQuest;

        levelToQPNeeded.push(0);
        levelToQPGainedPerQuest.push(0);

        for(uint256 i = 0; i < _maxQuestLevel - 1; i++) {
            levelToQPNeeded.push(_qpNeededForEachLevel[i]);
            levelToQPGainedPerQuest.push(_qpGainedAtEachLevel[i]);
        }
    }

    // Should be provided in order Easy, Medium, and Hard.
    function setGuaranteedDropAmounts(
        uint8[3] calldata _shardAmounts,
        uint8[3] calldata _starlightAmounts)
    external
    onlyAdminOrOwner
    {
        difficultyToStarlightAmount[QuestDifficulty.EASY] = _shardAmounts[0];
        difficultyToStarlightAmount[QuestDifficulty.MEDIUM] = _shardAmounts[1];
        difficultyToStarlightAmount[QuestDifficulty.HARD] = _shardAmounts[2];

        difficultyToShardAmount[QuestDifficulty.EASY] = _starlightAmounts[0];
        difficultyToShardAmount[QuestDifficulty.MEDIUM] = _starlightAmounts[1];
        difficultyToShardAmount[QuestDifficulty.HARD] = _starlightAmounts[2];
    }

    function setTreasureSettings(
        uint256 _treasureDropOdds,
        uint256 _universalLockDropOdds,
        uint256 _starlightId,
        uint256 _shardId,
        uint256 _universalLockId)
    external
    onlyAdminOrOwner {
        treasureDropOdds = _treasureDropOdds;
        starlightId = _starlightId;
        shardId = _shardId;
        universalLockDropOdds = _universalLockDropOdds;
        universalLockId = _universalLockId;
    }

    function setLPNeeded(uint256[3] calldata _lpNeeded) external onlyAdminOrOwner {
        difficultyToLPNeeded[QuestDifficulty.EASY] = _lpNeeded[0];
        difficultyToLPNeeded[QuestDifficulty.MEDIUM] = _lpNeeded[1];
        difficultyToLPNeeded[QuestDifficulty.HARD] = _lpNeeded[2];
    }

    function setTierOddsForDifficulty(
        uint256[5] calldata _easyTierOdds,
        uint256[5] calldata _mediumTierOdds,
        uint256[5] calldata _hardTierOdds)
    external
    onlyAdminOrOwner
    {
       difficultyToTierOdds[QuestDifficulty.EASY] = _easyTierOdds;
       difficultyToTierOdds[QuestDifficulty.MEDIUM] = _mediumTierOdds;
       difficultyToTierOdds[QuestDifficulty.HARD] = _hardTierOdds;
    }

    function setAutoQuestLoops(uint256[] calldata _availableLoops) external onlyAdminOrOwner {
        uint256[] memory _oldValues = availableAutoQuestLoops.values();
        for(uint256 i = 0; i < _oldValues.length; i++) {
            availableAutoQuestLoops.remove(_oldValues[i]);
        }

        for(uint256 i = 0; i < _availableLoops.length; i++) {
            availableAutoQuestLoops.add(_availableLoops[i]);
        }
    }

    function setRecruitSettings(
        uint8 _recruitNumberOfStarlight,
        uint8 _recruitNumberOfCrystalShards,
        uint256 _recruitCrystalShardsOdds,
        uint256 _recruitUniversalLockOdds)
    external
    onlyAdminOrOwner
    {
        recruitNumberOfStarlight = _recruitNumberOfStarlight;
        recruitNumberOfCrystalShards = _recruitNumberOfCrystalShards;
        recruitCrystalShardsOdds = _recruitCrystalShardsOdds;
        recruitUniversalLockOdds = _recruitUniversalLockOdds;
    }
}
