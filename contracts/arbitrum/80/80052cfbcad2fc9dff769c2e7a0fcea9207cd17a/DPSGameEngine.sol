//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "./Ownable.sol";
import "./DPSStructs.sol";
import "./DPSInterfaces.sol";
import "./IERC20MintableBurnable.sol";
import "./console.sol";

contract DPSGameEngine is DPSGameEngineI, Ownable {
    DPSQRNGI public random;
    DPSSupportShipI public supportShip;
    MintableBurnableIERC1155 public artifact;
    DPSCartographerI public cartographer;
    DPSGameSettingsI public gameSettings;
    DPSGameEngineI public gameEngine;
    DPSDocksI public docks;
    IERC20MintableBurnable public doubloons;
    DPSChestsIV2 public chests;
    address public treasury;
    address public plunderers;

    /// @notice an array that keeps for each pirate contract, a contract to get the features out of
    mapping(IERC721 => DPSPirateFeaturesI) public featuresPerPirate;

    event SetContract(uint256 _target, address _contract);
    event TreasuryUpdate(uint256 _amount);
    event WonLockBocks(address indexed _user, uint256 _amount);
    event ChangedTreasury(address _newTreasury);
    event OpenedLockBox(address indexed _owner, ARTIFACT_TYPE _type);
    event FeaturesPerPirateChanged(IERC721 indexed _pirate, DPSPirateFeaturesI _feature);

    /**
     * @notice computes skills for the flagship based on the level of the part of the flagship + base skills of the flagship
     * @param levels levels for each part, needs to respect the order of the levels from flagship
     * @param _claimingRewardsCache the cache object that contains the skill points per skill type
     * @return cached object with the skill points updated
     */
    function computeFlagShipSkills(uint8[7] memory levels, VoyageStatusCache memory _claimingRewardsCache)
        private
        view
        returns (VoyageStatusCache memory)
    {
        unchecked {
            uint16[7] memory skillsPerPart = gameSettings.getSkillsPerFlagshipParts();
            uint8[7] memory skillTypes = gameSettings.getSkillTypeOfEachFlagshipPart();
            uint256 flagshipBaseSkills = gameSettings.flagshipBaseSkills();
            _claimingRewardsCache.luck += flagshipBaseSkills;
            _claimingRewardsCache.navigation += flagshipBaseSkills;
            _claimingRewardsCache.strength += flagshipBaseSkills;
            for (uint256 i; i < 7; ++i) {
                if (skillTypes[i] == uint8(SKILL_TYPE.LUCK)) _claimingRewardsCache.luck += skillsPerPart[i] * levels[i];
                if (skillTypes[i] == uint8(SKILL_TYPE.NAVIGATION))
                    _claimingRewardsCache.navigation += skillsPerPart[i] * levels[i];
                if (skillTypes[i] == uint8(SKILL_TYPE.STRENGTH))
                    _claimingRewardsCache.strength += skillsPerPart[i] * levels[i];
            }
            return _claimingRewardsCache;
        }
    }

    /**
     * @notice computes skills for the support ships as there are multiple types that apply skills to different skill type: navigation, luck, strength
     * @param _supportShips the array of support ships
     * @param _artifactIds the array of artifacts
     * @param _claimingRewardsCache the cache object that contains the skill points per skill type
     * @return cached object with the skill points updated
     */
    function computeSupportSkills(
        uint8[9] memory _supportShips,
        uint16[13] memory _artifactIds,
        VoyageStatusCache memory _claimingRewardsCache
    ) private view returns (VoyageStatusCache memory) {
        unchecked {
            uint16 skill;
            for (uint256 i = 1; i < 13; ++i) {
                ARTIFACT_TYPE _type = ARTIFACT_TYPE(i);
                if (_artifactIds[i] == 0) continue;
                skill = gameSettings.artifactsSkillBoosts(_type);
                if (
                    _type == ARTIFACT_TYPE.COMMON_STRENGTH ||
                    _type == ARTIFACT_TYPE.RARE_STRENGTH ||
                    _type == ARTIFACT_TYPE.EPIC_STRENGTH ||
                    _type == ARTIFACT_TYPE.LEGENDARY_STRENGTH
                ) _claimingRewardsCache.strength += skill * _artifactIds[i];

                if (
                    _type == ARTIFACT_TYPE.COMMON_LUCK ||
                    _type == ARTIFACT_TYPE.RARE_LUCK ||
                    _type == ARTIFACT_TYPE.EPIC_LUCK ||
                    _type == ARTIFACT_TYPE.LEGENDARY_LUCK
                ) _claimingRewardsCache.luck += skill * _artifactIds[i];

                if (
                    _type == ARTIFACT_TYPE.COMMON_NAVIGATION ||
                    _type == ARTIFACT_TYPE.RARE_NAVIGATION ||
                    _type == ARTIFACT_TYPE.EPIC_NAVIGATION ||
                    _type == ARTIFACT_TYPE.LEGENDARY_NAVIGATION
                ) _claimingRewardsCache.navigation += skill * _artifactIds[i];
            }

            for (uint256 i; i < 9; ++i) {
                if (_supportShips[i] == 0) continue;
                SUPPORT_SHIP_TYPE supportShipType = SUPPORT_SHIP_TYPE(i);
                skill = gameSettings.supportShipsSkillBoosts(supportShipType);
                if (
                    supportShipType == SUPPORT_SHIP_TYPE.SLOOP_STRENGTH ||
                    supportShipType == SUPPORT_SHIP_TYPE.CARAVEL_STRENGTH ||
                    supportShipType == SUPPORT_SHIP_TYPE.GALLEON_STRENGTH
                ) _claimingRewardsCache.strength += skill * _supportShips[i];

                if (
                    supportShipType == SUPPORT_SHIP_TYPE.SLOOP_LUCK ||
                    supportShipType == SUPPORT_SHIP_TYPE.CARAVEL_LUCK ||
                    supportShipType == SUPPORT_SHIP_TYPE.GALLEON_LUCK
                ) _claimingRewardsCache.luck += skill * _supportShips[i];

                if (
                    supportShipType == SUPPORT_SHIP_TYPE.SLOOP_NAVIGATION ||
                    supportShipType == SUPPORT_SHIP_TYPE.CARAVEL_NAVIGATION ||
                    supportShipType == SUPPORT_SHIP_TYPE.GALLEON_NAVIGATION
                ) _claimingRewardsCache.navigation += skill * _supportShips[i];
            }
            return _claimingRewardsCache;
        }
    }

    /**
     * @notice interprets a randomness result, meaning that based on the skill points accumulated from base pirate skills,
     *         flagship + support ships, we do a comparison between the result of the randomness and the skill points.
     *         if random > skill points than this interaction fails. Things to notice: if STORM or ENEMY fails then we
     *         destroy a support ship (if exists) or do health damage of 100% which will result in skipping all the upcoming
     *         interactions
     * @param _result - random number generated
     * @param _voyageResult - the result object that is cached and sent along for later on saving into storage
     * @param _lockedVoyage - locked voyage that contains the support ship objects that will get modified (sent as storage) if interaction failed
     * @param _claimingRewardsCache - cache object sent along for points updates
     * @param _interaction - interaction that we compute the outcome for
     * @param _index - current index of interaction, used to update the outcome
     * @return updated voyage results and claimingRewardsCache (this updates in case of a support ship getting destroyed)
     */
    function interpretResults(
        uint256 _result,
        VoyageResult memory _voyageResult,
        LockedVoyageV2 memory _lockedVoyage,
        VoyageStatusCache memory _claimingRewardsCache,
        INTERACTION _interaction,
        uint256 _randomNumber,
        uint256 _index
    ) private view returns (VoyageResult memory, VoyageStatusCache memory) {
        if (_interaction == INTERACTION.CHEST && _result <= _claimingRewardsCache.luck) {
            _voyageResult.awardedChests++;
            _voyageResult.interactionResults[_index] = 1;
        } else if (
            (_interaction == INTERACTION.STORM && _result > _claimingRewardsCache.navigation) ||
            (_interaction == INTERACTION.ENEMY && _result > _claimingRewardsCache.strength)
        ) {
            if (_lockedVoyage.totalSupportShips - _voyageResult.totalSupportShipsDestroyed > 0) {
                _voyageResult.totalSupportShipsDestroyed++;
                uint256 supportShipTypesLength;
                for (uint256 i; i < 9; ++i) {
                    if (
                        _lockedVoyage.supportShips[i] > _voyageResult.destroyedSupportShips[i] &&
                        _lockedVoyage.supportShips[i] - _voyageResult.destroyedSupportShips[i] > 0
                    ) supportShipTypesLength++;
                }

                uint256[] memory supportShipTypes = new uint256[](supportShipTypesLength);
                uint256 j;
                for (uint256 i; i < 9; ++i) {
                    if (
                        _lockedVoyage.supportShips[i] > _voyageResult.destroyedSupportShips[i] &&
                        _lockedVoyage.supportShips[i] - _voyageResult.destroyedSupportShips[i] > 0
                    ) {
                        supportShipTypes[j] = i;
                        j++;
                    }
                }

                uint256 chosenType = random.getRandomNumber(
                    _randomNumber,
                    _lockedVoyage.lockedBlock,
                    string(abi.encode("SUPPORT_SHIP_", _index)),
                    uint8(1),
                    supportShipTypesLength
                ) % (supportShipTypesLength);

                SUPPORT_SHIP_TYPE supportShipType = SUPPORT_SHIP_TYPE.SLOOP_STRENGTH;
                for (uint256 i; i < supportShipTypesLength; ++i) {
                    if (chosenType == i) {
                        supportShipType = SUPPORT_SHIP_TYPE(supportShipTypes[i]);
                    }
                }
                _voyageResult.destroyedSupportShips[uint8(supportShipType)]++;
                _voyageResult.intDestroyedSupportShips[_index] = uint8(supportShipType);

                uint16 points = gameSettings.supportShipsSkillBoosts(supportShipType);

                if (
                    supportShipType == SUPPORT_SHIP_TYPE.SLOOP_STRENGTH ||
                    supportShipType == SUPPORT_SHIP_TYPE.CARAVEL_STRENGTH ||
                    supportShipType == SUPPORT_SHIP_TYPE.GALLEON_STRENGTH
                ) _claimingRewardsCache.strength -= points;
                else if (
                    supportShipType == SUPPORT_SHIP_TYPE.SLOOP_LUCK ||
                    supportShipType == SUPPORT_SHIP_TYPE.CARAVEL_LUCK ||
                    supportShipType == SUPPORT_SHIP_TYPE.GALLEON_LUCK
                ) _claimingRewardsCache.luck -= points;
                else if (
                    supportShipType == SUPPORT_SHIP_TYPE.SLOOP_NAVIGATION ||
                    supportShipType == SUPPORT_SHIP_TYPE.CARAVEL_NAVIGATION ||
                    supportShipType == SUPPORT_SHIP_TYPE.GALLEON_NAVIGATION
                ) _claimingRewardsCache.navigation -= points;
            } else {
                _voyageResult.healthDamage = 100;
            }
        } else if (_interaction != INTERACTION.CHEST) {
            _voyageResult.interactionResults[_index] = 1;
        }

        // console.log("int  ", uint8(_interaction));
        // console.log("int res ", _voyageResult.interactionResults[_index]);
        return (_voyageResult, _claimingRewardsCache);
    }

    function debuffVoyage(uint16 _voyageType, VoyageStatusCache memory _claimingRewardsCache)
        private
        view
        returns (VoyageStatusCache memory)
    {
        uint16 debuffs = gameSettings.voyageDebuffs(uint256(_voyageType));

        if (_claimingRewardsCache.strength > debuffs) _claimingRewardsCache.strength -= debuffs;
        else _claimingRewardsCache.strength = 0;

        if (_claimingRewardsCache.luck > debuffs) _claimingRewardsCache.luck -= debuffs;
        else _claimingRewardsCache.luck = 0;

        if (_claimingRewardsCache.navigation > debuffs) _claimingRewardsCache.navigation -= debuffs;
        else _claimingRewardsCache.navigation = 0;
        return _claimingRewardsCache;
    }

    function sanityCheckLockVoyages(
        LockedVoyageV2 memory _existingVoyage,
        LockedVoyageV2 memory _finishedVoyage,
        LockedVoyageV2 memory _lockedVoyage,
        VoyageConfigV2 memory _voyageConfig,
        uint256 _totalSupportShips,
        DPSFlagshipI _flagship
    ) external view override {
        // if flagship is unhealthy
        if (_flagship.getPartsLevel(_lockedVoyage.flagshipId)[uint256(FLAGSHIP_PART.HEALTH)] != 100) revert Unhealthy();

        // if it is already started
        if (_existingVoyage.voyageId != 0) revert WrongState(1);

        // if it is already finished
        if (_finishedVoyage.voyageId != 0) revert WrongState(2);

        uint256 numberOfVoyages;
        for (uint256 i; i < 13; ++i) {
            if (_lockedVoyage.artifactIds[i] > 0) numberOfVoyages += _lockedVoyage.artifactIds[i];
        }

        if (numberOfVoyages > gameSettings.maxArtifactsPerVoyage(_voyageConfig.typeOfVoyage)) revert WrongParams(1);

        // too many support ships
        if (
            _totalSupportShips > gameSettings.maxSupportShipsPerVoyageType(_voyageConfig.typeOfVoyage) ||
            _totalSupportShips != _lockedVoyage.totalSupportShips
        ) revert WrongState(3);

        uint256 totalArtifacts;
        for (uint256 i; i < _lockedVoyage.artifactIds.length; ++i) {
            totalArtifacts += _lockedVoyage.artifactIds[i];
        }

        if (
            _totalSupportShips > gameSettings.maxSupportShipsPerVoyageType(_voyageConfig.typeOfVoyage) ||
            _totalSupportShips != _lockedVoyage.totalSupportShips
        ) revert WrongState(4);
    }

    /**
     * @notice computing voyage state based on the locked voyage skills and config and causality params
     * @param _lockedVoyage - locked voyage items
     * @param _sequence - sequence of interactions
     * @param _randomNumber - the random number generated for this voyage
     * @return VoyageResult - containing the results of a voyage based on interactions
     */
    function computeVoyageState(
        LockedVoyageV2 memory _lockedVoyage,
        uint8[] memory _sequence,
        uint256 _randomNumber
    ) external view override returns (VoyageResult memory) {
        uint16[3] memory features;
        if (
            keccak256(bytes(_lockedVoyage.pirate.symbol())) == keccak256(bytes("DPS")) ||
            keccak256(bytes(_lockedVoyage.pirate.symbol())) == keccak256(bytes("LDPS"))
        ) {
            DPSPirateFeaturesI dpsFeatures = featuresPerPirate[_lockedVoyage.pirate];
            (, features) = dpsFeatures.getTraitsAndSkills(uint16(_lockedVoyage.dpsId));
        } else {
            features[0] = 150;
            features[1] = 150;
            features[2] = 150;
        }
        VoyageStatusCache memory claimingRewardsCache;
        // console.log("random number ", _randomNumber);
        // console.log("locked timestamp ", _lockedVoyage.lockedTimestamp);

        // traits not set
        if (features[0] == 0 || features[1] == 0 || features[2] == 0) revert WrongState(6);
        unchecked {
            claimingRewardsCache.luck += features[0];
            claimingRewardsCache.navigation += features[1];
            claimingRewardsCache.strength += features[2];
            // console.log("strength ", claimingRewardsCache.strength);
            // console.log("navigation ", claimingRewardsCache.navigation);
            // console.log("luck ", claimingRewardsCache.luck);
            claimingRewardsCache = computeFlagShipSkills(
                _lockedVoyage.flagship.getPartsLevel(_lockedVoyage.flagshipId),
                claimingRewardsCache
            );
            // console.log("strength ", claimingRewardsCache.strength);
            // console.log("navigation ", claimingRewardsCache.navigation);
            // console.log("luck ", claimingRewardsCache.luck);
            claimingRewardsCache = computeSupportSkills(
                _lockedVoyage.supportShips,
                _lockedVoyage.artifactIds,
                claimingRewardsCache
            );

            VoyageResult memory voyageResult;
            uint256 maxRollCap = gameSettings.maxRollCap();
            voyageResult.interactionResults = new uint8[](_sequence.length);
            voyageResult.interactionRNGs = new uint16[](_sequence.length);
            voyageResult.intDestroyedSupportShips = new uint8[](_sequence.length);
            // console.log("strength ", claimingRewardsCache.strength);
            // console.log("navigation ", claimingRewardsCache.navigation);
            // console.log("luck ", claimingRewardsCache.luck);
            claimingRewardsCache = debuffVoyage(_lockedVoyage.voyageType, claimingRewardsCache);
            // console.log("strength ", claimingRewardsCache.strength);
            // console.log("navigation ", claimingRewardsCache.navigation);
            // console.log("luck ", claimingRewardsCache.luck);
            claimingRewardsCache = applyMaxSkillCap(claimingRewardsCache);

            for (uint256 i; i < _sequence.length; ++i) {
                INTERACTION interaction = INTERACTION(_sequence[i]);
                if (interaction == INTERACTION.NONE || voyageResult.healthDamage == 100) {
                    voyageResult.skippedInteractions++;
                    continue;
                }

                claimingRewardsCache.entropy = string(abi.encode("INTERACTION_RESULT_", i, "_", _lockedVoyage.voyageId));
                uint256 result = random.getRandomNumber(
                    _randomNumber,
                    _lockedVoyage.lockedBlock,
                    claimingRewardsCache.entropy,
                    0,
                    maxRollCap
                );
                // console.log("result ", result);
                (voyageResult, claimingRewardsCache) = interpretResults(
                    result,
                    voyageResult,
                    _lockedVoyage,
                    claimingRewardsCache,
                    interaction,
                    _randomNumber,
                    i
                );
                voyageResult.interactionRNGs[i] = uint16(result);
            }
            return voyageResult;
        }
    }

    function rewardChest(
        uint256 _randomNumber,
        uint256 _amount,
        uint256 voyageType,
        address _owner
    ) external override {
        if (msg.sender != plunderers && msg.sender != owner()) revert Unauthorized();
        uint256 maxRoll = gameSettings.maxRollPerChest(voyageType);
        uint256 rewardedLockBox = 0;
        uint256 doubloonsRewards;

        for (uint256 i; i < _amount; ++i) {
            uint256 result = random.getRandomNumber(
                _randomNumber,
                block.number,
                string(abi.encode("REWARDS_TYPE_", i)),
                0,
                10000
            );

            if (result <= maxRoll) rewardedLockBox++;
        }
        doubloonsRewards = gameSettings.chestDoubloonRewards(voyageType) * _amount;

        if (doubloonsRewards > 0) {
            doubloons.mint(_owner, doubloonsRewards);

            uint256 doubloonsRewardForTreasury = (doubloonsRewards * 5) / 100;
            // 5% goes is minted to the treasury
            doubloons.mint(treasury, doubloonsRewardForTreasury);
            emit TreasuryUpdate(doubloonsRewardForTreasury);
        }

        if (rewardedLockBox > 0) {
            // minting lock boxes
            chests.mint(_owner, 4, rewardedLockBox);
            emit WonLockBocks(_owner, rewardedLockBox);
        }
    }

    function rewardLockedBox(
        uint256 _randomNumber,
        uint256 _amount,
        address _owner
    ) external override {
        if (msg.sender != plunderers && msg.sender != owner()) revert Unauthorized();
        ARTIFACT_TYPE[] memory artifacts = new ARTIFACT_TYPE[](_amount);

        for (uint i; i < _amount; ++i) {
            uint256 result = random.getRandomNumber(
                _randomNumber,
                block.number,
                string(abi.encode("LOCK_BOX_", i)),
                0,
                gameSettings.maxRollCapLockBoxes()
            );
            artifacts[i] = interpretLockedBoxResult(result);

            // we burn the lock box
        }

        for (uint i; i < _amount; ++i) {
            ARTIFACT_TYPE rewardType = artifacts[i];
            if (rewardType == ARTIFACT_TYPE.NONE) continue;
            artifact.mint(_owner, uint256(rewardType), 1);
            emit OpenedLockBox(_owner, rewardType);
        }
    }

    /**
     * @notice determines what type of artifact to give as reward
     * @param _result of randomness
     */
    function interpretLockedBoxResult(uint256 _result) internal view returns (ARTIFACT_TYPE) {
        unchecked {
            for (uint256 i = 1; i <= 12; ++i) {
                uint16[2] memory limits = gameSettings.getLockBoxesDistribution(ARTIFACT_TYPE(i));
                if (_result >= limits[0] && _result <= limits[1]) return ARTIFACT_TYPE(i);
            }
            return ARTIFACT_TYPE.NONE;
        }
    }

    function getLockedVoyageByOwnerAndId(
        address _owner,
        uint256 _voyageId,
        DPSVoyageIV2 _voyage
    ) external view returns (LockedVoyageV2 memory locked) {
        LockedVoyageV2[] memory cachedVoyages = docks.getLockedVoyagesForOwner(_owner, 0, _voyage.maxMintedId());
        for (uint256 i; i < cachedVoyages.length; ++i) {
            if (cachedVoyages[i].voyageId == _voyageId) return cachedVoyages[i];
        }
    }

    function getFinishedVoyageByOwnerAndId(
        address _owner,
        uint256 _voyageId,
        DPSVoyageIV2 _voyage
    ) external view returns (LockedVoyageV2 memory locked) {
        LockedVoyageV2[] memory cachedVoyages = docks.getFinishedVoyagesForOwner(_owner, 0, _voyage.maxMintedId());
        for (uint256 i; i < cachedVoyages.length; ++i) {
            if (cachedVoyages[i].voyageId == _voyageId) return cachedVoyages[i];
        }
    }

    function applyMaxSkillCap(VoyageStatusCache memory _claimingRewardsCache)
        internal
        view
        returns (VoyageStatusCache memory modifiedCached)
    {
        uint256 maxSkillsCap = gameSettings.maxSkillsCap();
        if (_claimingRewardsCache.navigation > maxSkillsCap) _claimingRewardsCache.navigation = maxSkillsCap;

        if (_claimingRewardsCache.luck > maxSkillsCap) _claimingRewardsCache.luck = maxSkillsCap;

        if (_claimingRewardsCache.strength > maxSkillsCap) _claimingRewardsCache.strength = maxSkillsCap;
        modifiedCached = _claimingRewardsCache;
    }

    /**
     * SETTERS & GETTERS
     */
    function setContract(address _contract, uint8 _target) external onlyOwner {
        if (_target == 1) random = DPSQRNGI(_contract);
        else if (_target == 2) supportShip = DPSSupportShipI(_contract);
        else if (_target == 3) artifact = MintableBurnableIERC1155(_contract);
        else if (_target == 4) gameSettings = DPSGameSettingsI(_contract);
        else if (_target == 5) cartographer = DPSCartographerI(_contract);
        else if (_target == 6) chests = DPSChestsIV2(_contract);
        else if (_target == 7) docks = DPSDocksI(_contract);
        else if (_target == 8) doubloons = IERC20MintableBurnable(_contract);
        else if (_target == 9) treasury = _contract;
        else if (_target == 10) plunderers = _contract;
        emit SetContract(_target, _contract);
    }

    function setFeaturesPerPirate(IERC721 _pirate, DPSPirateFeaturesI _feature) external onlyOwner {
        featuresPerPirate[_pirate] = _feature;
        emit FeaturesPerPirateChanged(_pirate, _feature);
    }
}

