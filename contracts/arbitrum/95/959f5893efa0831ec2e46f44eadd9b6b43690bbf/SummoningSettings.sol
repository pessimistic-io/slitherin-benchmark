//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SummoningContracts.sol";

abstract contract SummoningSettings is Initializable, SummoningContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __SummoningSettings_init() internal initializer {
        SummoningContracts.__SummoningContracts_init();
    }

    function setIsSummoningPaused(bool _isSummoningPaused) external onlyAdminOrOwner {
        isSummoningPaused = _isSummoningPaused;
    }

    function setSuccessSensitivity(uint256 _successSensitivity) external onlyAdminOrOwner {
        successSensitivity = _successSensitivity;
    }

    function setSummoningDurationIfFailed(uint256 _summoningDurationIfFailed) external onlyAdminOrOwner {
        summoningDurationIfFailed = _summoningDurationIfFailed;
    }

    function setSimpleSettings(
        uint256 _summoningDuration,
        uint256 _genesisMagicCost,
        uint256 _auxiliaryMagicCost,
        uint32 _auxiliaryMaxSummons,
        uint32 _genesisMaxSummons,
        uint256 _chanceAzuriteDustDrop,
        uint256 _azuriteDustId)
    external
    onlyAdminOrOwner
    {
        require(_chanceAzuriteDustDrop <= 100000, "Bad azurite odds");
        summoningDuration = _summoningDuration;
        chanceAzuriteDustDrop = _chanceAzuriteDustDrop;
        azuriteDustId = _azuriteDustId;

        generationToMagicCost[LegionGeneration.AUXILIARY] = _auxiliaryMagicCost;
        generationToMagicCost[LegionGeneration.GENESIS] = _genesisMagicCost;

        generationToMaxSummons[LegionGeneration.AUXILIARY] = _auxiliaryMaxSummons;
        generationToMaxSummons[LegionGeneration.GENESIS] = _genesisMaxSummons;
    }

    function setLPSteps(
        SummoningStep[] calldata _auxiliarySteps,
        SummoningStep[] calldata _genesisSteps)
    external
    onlyAdminOrOwner
    {
        require(_auxiliarySteps.length > 0, "Bad auxiliary steps");
        require(_genesisSteps.length > 0, "Bad genesis steps");

        delete generationToLPRequiredSteps[LegionGeneration.AUXILIARY];
        delete generationToLPRequiredSteps[LegionGeneration.GENESIS];

        for(uint256 i = 0; i < _auxiliarySteps.length; i++) {
            generationToLPRequiredSteps[LegionGeneration.AUXILIARY].push(_auxiliarySteps[i]);
        }

        for(uint256 i = 0; i < _genesisSteps.length; i++) {
            generationToLPRequiredSteps[LegionGeneration.GENESIS].push(_genesisSteps[i]);
        }
    }

    function setCrystalOdds(
        uint256[] calldata _crystalIds,
        uint256[] calldata _crystalTimeReductions,
        uint256[3][] calldata _crystalIdToOdds)
    external
    onlyAdminOrOwner
    {
        require(_crystalIds.length == _crystalIdToOdds.length
            && _crystalIds.length == _crystalTimeReductions.length, "Summoning: Bad crystal lengths");

        delete crystalIds;

        for(uint256 i = 0; i < _crystalIds.length; i++) {
            crystalIds.add(_crystalIds[i]);
            crystalIdToTimeReduction[_crystalIds[i]] = _crystalTimeReductions[i];
            for(uint256 j = 0; j < 3; j++) {
                crystalIdToChangedOdds[_crystalIds[i]][j] = _crystalIdToOdds[i][j];
            }
        }
    }

    // The odds should be for COMMON, UNCOMMON, RARE in that order. The storage is setup to be able to handle summoning more rarities than that,
    // but we do not have a need right now. Can upgrade contract later.
    function setSummoningOdds(
        LegionRarity[] calldata _inputRarities,
        uint256[] calldata _genesisOdds,
        uint256[] calldata _auxiliaryOdds)
    external
    onlyAdminOrOwner
    {
        // Only 3 output options per input rarity
        require(_inputRarities.length > 0
            && _genesisOdds.length == _inputRarities.length * 3
            && _auxiliaryOdds.length == _genesisOdds.length, "Bad input data");

        for(uint256 i = 0; i < _inputRarities.length; i++) {
            LegionRarity _inputRarity = _inputRarities[i];

            rarityToGenerationToOddsPerRarity[_inputRarity][LegionGeneration.GENESIS][LegionRarity.COMMON] = _genesisOdds[i * 3];
            rarityToGenerationToOddsPerRarity[_inputRarity][LegionGeneration.GENESIS][LegionRarity.UNCOMMON] = _genesisOdds[(i * 3) + 1];
            rarityToGenerationToOddsPerRarity[_inputRarity][LegionGeneration.GENESIS][LegionRarity.RARE] = _genesisOdds[(i * 3) + 2];

            rarityToGenerationToOddsPerRarity[_inputRarity][LegionGeneration.AUXILIARY][LegionRarity.COMMON] = _auxiliaryOdds[i * 3];
            rarityToGenerationToOddsPerRarity[_inputRarity][LegionGeneration.AUXILIARY][LegionRarity.UNCOMMON] = _auxiliaryOdds[(i * 3) + 1];
            rarityToGenerationToOddsPerRarity[_inputRarity][LegionGeneration.AUXILIARY][LegionRarity.RARE] = _auxiliaryOdds[(i * 3) + 2];
        }
    }

    function setSummoningFatigue(
        uint256 _summoningFatigueCooldown)
    external
    onlyAdminOrOwner
    {
        summoningFatigueCooldown = _summoningFatigueCooldown;
    }
}
