//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CraftingDiamondState.sol";

contract CraftingDiamondSettings is Initializable, CraftingDiamondState {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

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
        CraftingReward[] calldata _hardRewards,
        CraftingReward[] calldata _prismSmallToMediumRewards,
        CraftingReward[] calldata _prismMediumToLargeRewards)
    external
    onlyAdminOrOwner
    {

        RecipeDifficulty[5] memory _difficulties = [
            RecipeDifficulty.EASY,
            RecipeDifficulty.MEDIUM,
            RecipeDifficulty.HARD,
            RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM,
            RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE
        ];

        for(uint256 i = 0; i < _difficulties.length; i++) {
            delete difficultyToRewards[_difficulties[i]];

            CraftingReward[] memory _rewardsForDifficulty;
            if(_difficulties[i] == RecipeDifficulty.EASY) {
                _rewardsForDifficulty = _easyRewards;
            } else if(_difficulties[i] == RecipeDifficulty.MEDIUM) {
                _rewardsForDifficulty = _mediumRewards;
            } else if(_difficulties[i] == RecipeDifficulty.HARD) {
                _rewardsForDifficulty = _hardRewards;
            } else if(_difficulties[i] == RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM) {
                _rewardsForDifficulty = _prismSmallToMediumRewards;
            } else {
                _rewardsForDifficulty = _prismMediumToLargeRewards;
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
        uint256[5] calldata _recipeLengths,
        uint256[5] calldata _successRates,
        uint8[5][5] calldata _treasureAmountPerTier,
        uint8[5] memory _levelUnlocked)
    external
    onlyAdminOrOwner
    {
        difficultyToRecipeLength[RecipeDifficulty.EASY] = _recipeLengths[0];
        difficultyToRecipeLength[RecipeDifficulty.MEDIUM] = _recipeLengths[1];
        difficultyToRecipeLength[RecipeDifficulty.HARD] = _recipeLengths[2];
        difficultyToRecipeLength[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = _recipeLengths[3];
        difficultyToRecipeLength[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = _recipeLengths[4];

        difficultyToSuccessRate[RecipeDifficulty.EASY] = _successRates[0];
        difficultyToSuccessRate[RecipeDifficulty.MEDIUM] = _successRates[1];
        difficultyToSuccessRate[RecipeDifficulty.HARD] = _successRates[2];
        difficultyToSuccessRate[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = _successRates[3];
        difficultyToSuccessRate[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = _successRates[4];

        for(uint256 i = 0; i < 5; i++) {
            difficultyToAmountPerTier[RecipeDifficulty.EASY][i] = _treasureAmountPerTier[0][i];
            difficultyToAmountPerTier[RecipeDifficulty.MEDIUM][i] = _treasureAmountPerTier[1][i];
            difficultyToAmountPerTier[RecipeDifficulty.HARD][i] = _treasureAmountPerTier[2][i];
            difficultyToAmountPerTier[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM][i] = _treasureAmountPerTier[3][i];
            difficultyToAmountPerTier[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE][i] = _treasureAmountPerTier[4][i];
        }

        difficultyToLevelUnlocked[RecipeDifficulty.EASY] = _levelUnlocked[0];
        difficultyToLevelUnlocked[RecipeDifficulty.MEDIUM] = _levelUnlocked[1];
        difficultyToLevelUnlocked[RecipeDifficulty.HARD] = _levelUnlocked[2];
        difficultyToLevelUnlocked[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = _levelUnlocked[3];
        difficultyToLevelUnlocked[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = _levelUnlocked[4];
    }

    function setCraftingLevelSettings(
        uint8 _maxCraftingLevel,
        uint256[] calldata _levelToCPNeeded,
        uint256[5] calldata _difficultyToCPGainedPerRecipe)
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
        difficultyToCPGained[RecipeDifficulty.PRISM_UPGRADE_SMALL_TO_MEDIUM] = _difficultyToCPGainedPerRecipe[3];
        difficultyToCPGained[RecipeDifficulty.PRISM_UPGRADE_MEDIUM_TO_LARGE] = _difficultyToCPGainedPerRecipe[4];
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
