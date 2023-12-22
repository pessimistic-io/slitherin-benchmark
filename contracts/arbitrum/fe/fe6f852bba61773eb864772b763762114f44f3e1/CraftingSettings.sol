//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CraftingContracts.sol";

abstract contract CraftingSettings is Initializable, CraftingContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __CraftingSettings_init() internal initializer {
        CraftingContracts.__CraftingContracts_init();
    }

    function setSimpleSettings(
        uint256 _craftingFee,
        uint8 _percentReturnedOnFailure)
    external
    onlyAdminOrOwner
    {
        require(_percentReturnedOnFailure >= 0 && _percentReturnedOnFailure <= 100, "Bad refund percent");
        craftingFee = _craftingFee;
        percentReturnedOnFailure = _percentReturnedOnFailure;
    }

    function setRewards(
        CraftingReward[] calldata _easyRewards,
        CraftingReward[] calldata _mediumRewards,
        CraftingReward[] calldata _hardRewards)
    external
    onlyAdminOrOwner
    {

        RecipeDifficulty[3] memory _difficulties = [
            RecipeDifficulty.EASY,
            RecipeDifficulty.MEDIUM,
            RecipeDifficulty.HARD
        ];

        for(uint256 i = 0; i < _difficulties.length; i++) {
            delete difficultyToRewards[_difficulties[i]];

            CraftingReward[] memory _rewardsForDifficulty;
            if(_difficulties[i] == RecipeDifficulty.EASY) {
                _rewardsForDifficulty = _easyRewards;
            } else if(_difficulties[i] == RecipeDifficulty.MEDIUM) {
                _rewardsForDifficulty = _mediumRewards;
            } else {
                _rewardsForDifficulty = _hardRewards;
            }
            uint256 _totalRewardOdds = 0;
            for(uint256 j = 0; j < _rewardsForDifficulty.length; j++) {
                difficultyToRewards[_difficulties[i]].push(_rewardsForDifficulty[j]);
                _totalRewardOdds += _rewardsForDifficulty[j].odds;
            }

            require(_totalRewardOdds == 100000, "Bad odds");
        }
    }

    function setDifficultySettings(
        uint256[3] calldata _recipeLengths,
        uint256[3] calldata _successRates,
        uint8[5][3] calldata _treasureAmountPerTier,
        uint8[3] memory _levelUnlocked)
    external
    onlyAdminOrOwner
    {
        difficultyToRecipeLength[RecipeDifficulty.EASY] = _recipeLengths[0];
        difficultyToRecipeLength[RecipeDifficulty.MEDIUM] = _recipeLengths[1];
        difficultyToRecipeLength[RecipeDifficulty.HARD] = _recipeLengths[2];

        difficultyToSuccessRate[RecipeDifficulty.EASY] = _successRates[0];
        difficultyToSuccessRate[RecipeDifficulty.MEDIUM] = _successRates[1];
        difficultyToSuccessRate[RecipeDifficulty.HARD] = _successRates[2];

        for(uint256 i = 0; i < 5; i++) {
            difficultyToAmountPerTier[RecipeDifficulty.EASY][i] = _treasureAmountPerTier[0][i];
            difficultyToAmountPerTier[RecipeDifficulty.MEDIUM][i] = _treasureAmountPerTier[1][i];
            difficultyToAmountPerTier[RecipeDifficulty.HARD][i] = _treasureAmountPerTier[2][i];
        }

        difficultyToLevelUnlocked[RecipeDifficulty.EASY] = _levelUnlocked[0];
        difficultyToLevelUnlocked[RecipeDifficulty.MEDIUM] = _levelUnlocked[1];
        difficultyToLevelUnlocked[RecipeDifficulty.HARD] = _levelUnlocked[2];
    }

    function setCraftingLevelSettings(
        uint8 _maxCraftingLevel,
        uint256[] calldata _levelToCPNeeded,
        uint256[3] calldata _difficultyToCPGainedPerRecipe)
    external
    onlyAdminOrOwner
    {
        require(_maxCraftingLevel > 0, "Bad max level");
        require(_levelToCPNeeded.length == _maxCraftingLevel - 1, "Not enough CP steps");

        maxCraftingLevel = _maxCraftingLevel;

        delete levelToCPNeeded;
        delete levelToCPGainedPerRecipe;

        levelToCPNeeded.push(0);
        levelToCPGainedPerRecipe.push(0);

        for(uint256 i = 0; i < _maxCraftingLevel - 1; i++) {
            levelToCPNeeded.push(_levelToCPNeeded[i]);
        }

        difficultyToCPGained[RecipeDifficulty.EASY] = _difficultyToCPGainedPerRecipe[0];
        difficultyToCPGained[RecipeDifficulty.MEDIUM] = _difficultyToCPGainedPerRecipe[1];
        difficultyToCPGained[RecipeDifficulty.HARD] = _difficultyToCPGainedPerRecipe[2];
    }

    function setDifficultyAndGenerationReward(
        RecipeDifficulty _difficulty,
        LegionGeneration _generation,
        CraftingReward[] calldata _rewards)
    external
    onlyAdminOrOwner
    {
        delete difficultyToGenerationToRewards[_difficulty][_generation];

        for(uint256 i = 0; i < _rewards.length; i++) {
            difficultyToGenerationToRewards[_difficulty][_generation].push(_rewards[i]);
        }
    }
}
