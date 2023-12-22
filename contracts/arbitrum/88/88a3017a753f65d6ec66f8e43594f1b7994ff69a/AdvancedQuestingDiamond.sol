//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdvancedQuestingDiamondState.sol";
import "./IAdvancedQuestingInternal.sol";

contract AdvancedQuestingDiamond is Initializable, AdvancedQuestingDiamondState {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        AdvancedQuestingDiamondState.__AdvancedQuestingDiamondState_init();
    }

    function startAdvancedQuesting(LibAdvancedQuestingDiamond.StartQuestParams[] calldata _params)
    external
    whenNotPaused
    onlyEOA
    {
        require(_params.length > 0, "No start quest params given");

        for(uint256 i = 0; i < _params.length; i++) {
            _startAdvancedQuesting(_params[i], false);
        }
    }

    function _startAdvancedQuesting(LibAdvancedQuestingDiamond.StartQuestParams memory _startQuestParams, bool _isRestarting) private {
        uint256 _legionId = _startQuestParams.legionId;

        require(!isLegionQuesting(_legionId), "Legion is already questing");
        require(isValidZone(_startQuestParams.zoneName), "Invalid zone");

        LegionMetadata memory _legionMetadata = appStorage.legionMetadataStore.metadataForLegion(_legionId);

        if(_legionMetadata.legionGeneration == LegionGeneration.RECRUIT) {
            _startAdvancedQuestingRecruit(_startQuestParams, _isRestarting);
        } else {
            _startAdvancedQuestingRegular(_startQuestParams, _isRestarting, _legionMetadata);
        }
    }

    function _startAdvancedQuestingRecruit(LibAdvancedQuestingDiamond.StartQuestParams memory _startQuestParams, bool _isRestarting) private {
        require(_startQuestParams.advanceToPart == 1, "Bad recruit part");

        require(_startQuestParams.treasureIds.length == 0 && _startQuestParams.treasureAmounts.length == 0,
            "Recruits cannot take treasures");

        uint256 _requestId = _createRequestAndSaveData(_startQuestParams);

        _transferLegionAndTreasures(_startQuestParams, _isRestarting);

        appStorage.numRecruitsQuesting++;

        emit AdvancedQuestStarted(
            msg.sender,
            _requestId,
            _startQuestParams);
    }

    function _startAdvancedQuestingRegular(LibAdvancedQuestingDiamond.StartQuestParams memory _startQuestParams, bool _isRestarting, LegionMetadata memory _legionMetadata) private {

        uint256 _numberOfParts = appStorage.zoneNameToInfo[_startQuestParams.zoneName].parts.length;
        require(_startQuestParams.advanceToPart > 0 && _startQuestParams.advanceToPart <= _numberOfParts,
            "Invalid advance to part");

        bool _willPlayTreasureTriad = false;

        // Need to check that they have the correct level to advance through the given parts of the quest.
        for(uint256 i = 0; i < _startQuestParams.advanceToPart; i++) {
            uint8 _levelRequirement = appStorage.zoneNameToInfo[_startQuestParams.zoneName].parts[i].questingLevelRequirement;

            require(_legionMetadata.questLevel >= _levelRequirement, "Legion not high enough questing level");

            bool _treasureTriadOnThisPart = appStorage.zoneNameToInfo[_startQuestParams.zoneName].parts[i].playTreasureTriad;

            _willPlayTreasureTriad = _willPlayTreasureTriad || _treasureTriadOnThisPart;

            // Also, if a part has a treasure triad game and it is not the last part, they cannot auto advance past it.
            if(i < _startQuestParams.advanceToPart - 1 && _treasureTriadOnThisPart) {

                revert("Cannot advanced past a part that requires treasure triad");
            }
        }

        require(_startQuestParams.treasureIds.length == _startQuestParams.treasureAmounts.length
            && (!_willPlayTreasureTriad || _startQuestParams.treasureIds.length > 0),
            "Bad treasure lengths");

        uint256 _totalTreasureAmounts = 0;
        uint8 _maxConstellationRank = _maxConstellationRankForLegionAndZone(_startQuestParams.zoneName, _legionMetadata);

        for(uint256 i = 0; i < _startQuestParams.treasureIds.length; i++) {
            require(_startQuestParams.treasureIds[i] > 0 && _startQuestParams.treasureAmounts[i] > 0);

            _totalTreasureAmounts += _startQuestParams.treasureAmounts[i];

            require(_totalTreasureAmounts <= _maxConstellationRank, "Too many treasures");
        }

        uint256 _requestId = _createRequestAndSaveData(_startQuestParams);

        _saveStakedTreasures(_startQuestParams);

        _transferLegionAndTreasures(_startQuestParams, _isRestarting);

        appStorage.numQuesting++;

        emit AdvancedQuestStarted(
            msg.sender,
            _requestId,
            _startQuestParams);
    }

    function _transferLegionAndTreasures(LibAdvancedQuestingDiamond.StartQuestParams memory _startQuestParams, bool _isRestarting) private {
        if(_isRestarting) {
            return;
        }

        // Transfer legion and treasure to this contract.
        appStorage.legion.adminSafeTransferFrom(msg.sender, address(this), _startQuestParams.legionId);

        if(_startQuestParams.treasureIds.length > 0) {
            appStorage.treasure.safeBatchTransferFrom(
                msg.sender,
                address(this),
                _startQuestParams.treasureIds,
                _startQuestParams.treasureAmounts,
                "");
        }
    }

    function _createRequestAndSaveData(LibAdvancedQuestingDiamond.StartQuestParams memory _startQuestParams) private returns(uint256) {
        uint256 _legionId = _startQuestParams.legionId;
        uint256 _requestId = appStorage.randomizer.requestRandomNumber();

        appStorage.legionIdToLegionQuestingInfoV2[_legionId].startTime = uint120(block.timestamp);
        appStorage.legionIdToLegionQuestingInfoV2[_legionId].requestId = uint80(_requestId);
        appStorage.legionIdToLegionQuestingInfoV2[_legionId].zoneName = _startQuestParams.zoneName;
        appStorage.legionIdToLegionQuestingInfoV2[_legionId].owner = msg.sender;
        appStorage.legionIdToLegionQuestingInfoV2[_legionId].advanceToPart = _startQuestParams.advanceToPart;
        appStorage.legionIdToLegionQuestingInfoV2[_legionId].currentPart = 0;
        appStorage.legionIdToLegionQuestingInfoV2[_legionId].corruptionAmount = appStorage.corruption.balanceOf(address(this));
        delete appStorage.legionIdToLegionQuestingInfoV2[_legionId].timeTriadWasPlayed;
        delete appStorage.legionIdToLegionQuestingInfoV2[_legionId].corruptedCellsRemainingForCurrentPart;
        delete appStorage.legionIdToLegionQuestingInfoV2[_legionId].cardsFlipped;

        return _requestId;
    }

    function _saveStakedTreasures(
        LibAdvancedQuestingDiamond.StartQuestParams memory _startQuestParams)
    private
    {
        LibAdvancedQuestingDiamond.Treasures memory _treasures;

        uint256 _numberOfTreasures = _startQuestParams.treasureIds.length;
        _treasures.numberOfTypesOfTreasures = uint8(_numberOfTreasures);

        if(_numberOfTreasures > 0) {
            _treasures.treasure1Id = uint16(_startQuestParams.treasureIds[0]);
            _treasures.treasure1Amount = uint8(_startQuestParams.treasureAmounts[0]);
        }
        if(_numberOfTreasures > 1) {
            _treasures.treasure2Id = uint16(_startQuestParams.treasureIds[1]);
            _treasures.treasure2Amount = uint8(_startQuestParams.treasureAmounts[1]);
        }
        if(_numberOfTreasures > 2) {
            _treasures.treasure3Id = uint16(_startQuestParams.treasureIds[2]);
            _treasures.treasure3Amount = uint8(_startQuestParams.treasureAmounts[2]);
        }
        if(_numberOfTreasures > 3) {
            _treasures.treasure4Id = uint16(_startQuestParams.treasureIds[3]);
            _treasures.treasure4Amount = uint8(_startQuestParams.treasureAmounts[3]);
        }
        if(_numberOfTreasures > 4) {
            _treasures.treasure5Id = uint16(_startQuestParams.treasureIds[4]);
            _treasures.treasure5Amount = uint8(_startQuestParams.treasureAmounts[4]);
        }
        if(_numberOfTreasures > 5) {
            _treasures.treasure6Id = uint16(_startQuestParams.treasureIds[5]);
            _treasures.treasure6Amount = uint8(_startQuestParams.treasureAmounts[5]);
        }
        if(_numberOfTreasures > 6) {
            _treasures.treasure7Id = uint16(_startQuestParams.treasureIds[6]);
            _treasures.treasure7Amount = uint8(_startQuestParams.treasureAmounts[6]);
        }

        for(uint256 i = 0; i < _numberOfTreasures; i++) {
            for(uint256 j = i + 1; j < _numberOfTreasures; j++) {
                require(_startQuestParams.treasureIds[i] != _startQuestParams.treasureIds[j],
                    "Duplicate treasure id in array");
            }
        }

        appStorage.legionIdToLegionQuestingInfoV2[_startQuestParams.legionId].treasures = _treasures;
    }

    // Ends questing at the current part. Must have played triad if triad is required on current part.
    function endQuesting(
        uint256[] calldata _legionIds,
        bool[] calldata _restartQuesting)
    external
    whenNotPaused
    onlyEOA
    nonZeroLength(_legionIds)
    {
        require(_legionIds.length == _restartQuesting.length, "Bad array lengths");
        for(uint256 i = 0; i < _legionIds.length; i++) {
            _endQuesting(_legionIds[i], _restartQuesting[i]);
        }
    }

    function _endQuesting(uint256 _legionId, bool _restartQuesting) private {
        bool _usingOldSchema = _isUsingOldSchema(_legionId);

        string memory _zoneName = _activeZoneForLegion(_usingOldSchema, _legionId);

        LegionMetadata memory _legionMetadata = appStorage.legionMetadataStore.metadataForLegion(_legionId);
        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo = appStorage.zoneNameToInfo[_zoneName];

        require(_ownerForLegion(_usingOldSchema, _legionId) == msg.sender, "Legion is not yours");

        uint256 _randomNumber = appStorage.randomizer.revealRandomNumber(_requestIdForLegion(_usingOldSchema, _legionId));

        _ensureDoneWithCurrentPart(_legionId, _zoneName, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber, true);

        _endQuestingPostValidation(_legionId, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber, _restartQuesting);
    }

    function _endQuestingPostValidation(
        uint256 _legionId,
        bool _usingOldSchema,
        LegionMetadata memory _legionMetadata,
        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo,
        uint256 _randomNumber,
        bool _isRestarting)
    private
    {
        uint8 _endingPart = _advanceToPartForLegion(_usingOldSchema, _legionId);

        AdvancedQuestReward[] memory _earnedRewards;
        if(_legionMetadata.legionGeneration == LegionGeneration.RECRUIT) {
            // Level up recruit
            LibAdvancedQuestingDiamond.RecruitPartInfo storage _recruitPartInfo = appStorage.zoneNameToPartIndexToRecruitPartInfo[_activeZoneForLegion(_usingOldSchema, _legionId)][_endingPart - 1];

            if(_recruitPartInfo.recruitXPGained > 0) {
                appStorage.recruitLevel.increaseRecruitExp(_legionId, _recruitPartInfo.recruitXPGained);
            }

            _earnedRewards = _getRecruitEarnedRewards(_recruitPartInfo, _randomNumber, _legionId);

            appStorage.numRecruitsQuesting--;
        } else {
            appStorage.questing.processQPGainAndLevelUp(_legionId, _legionMetadata.questLevel, appStorage.endingPartToQPGained[_endingPart]);

            _earnedRewards = _getEarnedRewards(
                _legionId,
                _usingOldSchema,
                _endingPart,
                _zoneInfo,
                _legionMetadata,
                _randomNumber);

            if(_startTimeForLegion(_usingOldSchema, _legionId) > appStorage.timePoolsFirstSet) {
                appStorage.numQuesting--;
            }
        }

        // Only need to delete the start time to save on gas. Acts as a flag if the legion is questing.
        // When startQuesting is called all LegionQuestingInfo fields will be overridden.
        if(_usingOldSchema) {
            delete appStorage.legionIdToLegionQuestingInfoV1[_legionId].startTime;
        } else {
            delete appStorage.legionIdToLegionQuestingInfoV2[_legionId].startTime;
        }

        if(!_isRestarting) {
            // Send back legion and treasure
            appStorage.legion.adminSafeTransferFrom(address(this), msg.sender, _legionId);
        }

        (uint256[] memory _treasureIds, uint256[] memory _treasureAmounts) = IAdvancedQuestingInternal(address(this)).unstakeTreasures(_legionId, _usingOldSchema, _isRestarting, msg.sender);

        emit AdvancedQuestEnded(msg.sender, _legionId, _earnedRewards);

        if(_isRestarting) {
            _startAdvancedQuesting(LibAdvancedQuestingDiamond.StartQuestParams(_legionId, _activeZoneForLegion(_usingOldSchema, _legionId), _endingPart, _treasureIds, _treasureAmounts), _isRestarting);
        }
    }

    function _getRecruitEarnedRewards(LibAdvancedQuestingDiamond.RecruitPartInfo storage _recruitPartInfo, uint256 _randomNumber, uint256 _legionId) private returns(AdvancedQuestReward[] memory) {
        // The returned random number was used for stasis calculations. Scramble the number with a constant.
        _randomNumber = uint256(keccak256(abi.encode(_randomNumber,
            7647295972771752179227871979083739911846583376458796885201641052640283607576)));

        AdvancedQuestReward[] memory _rewards = new AdvancedQuestReward[](4);

        if(_recruitPartInfo.numEoS > 0) {
            appStorage.consumable.mint(msg.sender, EOS_ID, _recruitPartInfo.numEoS);

            _rewards[0].consumableId = EOS_ID;
            _rewards[0].consumableAmount = _recruitPartInfo.numEoS;
        }

        if(_recruitPartInfo.numShards > 0) {
            appStorage.consumable.mint(msg.sender, PRISM_SHARD_ID, _recruitPartInfo.numShards);

            _rewards[1].consumableId = PRISM_SHARD_ID;
            _rewards[1].consumableAmount = _recruitPartInfo.numShards;
        }

        RecruitType _recruitType = appStorage.recruitLevel.recruitType(_legionId);

        (,, uint32 _positiveTreasureBonus, uint32 _negativeTreasureBonus) = _getCorruptionEffects(appStorage.legionIdToLegionQuestingInfoV2[_legionId].corruptionAmount);

        bool _fragmentReceived = appStorage.masterOfInflation.tryMintFromPool(MintFromPoolParams(
            appStorage.tierToRecruitPoolId[5],
            1,
            (_recruitType != RecruitType.NONE ? appStorage.cadetRecruitFragmentBoost : 0) + _positiveTreasureBonus,
            _recruitPartInfo.fragmentId,
            _randomNumber,
            msg.sender,
            _negativeTreasureBonus
        ));

        if(_fragmentReceived) {
            _rewards[2].treasureFragmentId = _recruitPartInfo.fragmentId;
        }

        if(_recruitPartInfo.chanceUniversalLock > 0) {
            _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));

            uint256 _result = _randomNumber % 100000;

            if(_result < _recruitPartInfo.chanceUniversalLock) {
                appStorage.consumable.mint(msg.sender, 10, 1);

                _rewards[3].consumableId = 10;
                _rewards[3].consumableAmount = 1;
            }
        }

        return _rewards;
    }

    // A helper method. Was running into stack too deep errors.
    // Helps remove some of the local variables. Just enough to compile.
    function _getEarnedRewards(
        uint256 _legionId,
        bool _usingOldSchema,
        uint8 _endingPart,
        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo,
        LegionMetadata memory _legionMetadata,
        uint256 _randomNumber)
    private
    returns(AdvancedQuestReward[] memory)
    {
        return _distributeRewards(
            _activeZoneForLegion(_usingOldSchema, _legionId),
            _endingPart - 1,
            _zoneInfo.parts[_endingPart - 1],
            _legionMetadata,
            _randomNumber,
            _cardsFlippedForLegion(_usingOldSchema, _legionId),
            appStorage.legionIdToLegionQuestingInfoV2[_legionId].corruptionAmount
        );
    }

    function _distributeRewards(
        string memory _zoneName,
        uint256 _partIndex,
        LibAdvancedQuestingDiamond.ZonePart storage _endingPart,
        LegionMetadata memory _legionMetadata,
        uint256 _randomNumber,
        uint8 _cardsFlipped,
        uint256 _corruptionBalance)
    private
    returns(AdvancedQuestReward[] memory)
    {
        // The returned random number was used for stasis calculations. Scramble the number with a constant.
        _randomNumber = uint256(keccak256(abi.encode(_randomNumber,
            17647295972771752179227871979083739911846583376458796885201641052640283607576)));

        uint256 _legionGeneration = uint256(_legionMetadata.legionGeneration);
        uint256 _legionRarity = uint256(_legionMetadata.legionRarity);

        // Add 5 to the array length. 1 for the universal lock check, and 4 for potential rewards from multiple fragment tiers
        //
        AdvancedQuestReward[] memory _earnedRewards = new AdvancedQuestReward[](_endingPart.rewards.length + 5);
        uint256 _rewardIndexCur = 0;

        for(uint256 i = 0; i < _endingPart.rewards.length; i++) {
            LibAdvancedQuestingDiamond.ZoneReward storage _reward = _endingPart.rewards[i];

            uint256 _oddsBoost = uint256(_reward.generationToRarityToBoost[_legionGeneration][_legionRarity])
                + (uint256(_reward.boostPerFlippedCard) * uint256(_cardsFlipped))
                + appStorage.zoneNameToPartIndexToRewardIndexToQuestBoosts[_zoneName][_partIndex][i][_legionMetadata.questLevel];

            // This is the treasure fragment reward.
            // Go to the master of inflation contract instead of using the base odds here.
            //
            if(_reward.rewardOptions[0].treasureFragmentId > 0) {
                for(uint256 j = 0; j < _reward.rewardOptions.length; j++) {
                    if(_tryMintFragment(
                        _reward.rewardOptions[j].treasureFragmentId,
                        _oddsBoost,
                        _randomNumber,
                        msg.sender,
                        _corruptionBalance
                    ))
                    {
                        _earnedRewards[_rewardIndexCur] = AdvancedQuestReward(0, 0, _reward.rewardOptions[j].treasureFragmentId, 0);
                        if(j != _reward.rewardOptions.length - 1) {
                            _rewardIndexCur++;
                        }
                    }

                    _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
                }
            } else {
                uint256 _odds = uint256(_reward.baseRateRewardOdds) + _oddsBoost;

                bool _hitReward;

                if(_odds >= 255) {
                    _hitReward = true;
                } else if(_odds > 0) {
                    if(_randomNumber % 256 < _odds) {
                        _hitReward = true;
                    }
                    _randomNumber >>= 8;
                }

                if(_hitReward) {
                    _earnedRewards[_rewardIndexCur] = _mintHitReward(_pickRewardFromOptions(_randomNumber, _reward), _randomNumber, msg.sender);

                    _randomNumber >>= 8;
                }
            }

            _rewardIndexCur++;
        }

        // Check for universal lock win
        if(appStorage.chanceUniversalLock > 0) {
            _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));

            uint256 _result = _randomNumber % 100000;

            if(_result < appStorage.chanceUniversalLock) {
                appStorage.consumable.mint(msg.sender, 10, 1);

                _earnedRewards[_earnedRewards.length - 1] = AdvancedQuestReward(10, 1, 0, 0);
            }
        }

        return _earnedRewards;
    }

    function _tryMintFragment(
        uint256 _treasureFragmentId,
        uint256 _oddsBoost,
        uint256 _randomNumber,
        address _owner,
        uint256 _corruptionBalance
    ) private returns(bool) {
        (,, uint32 _positiveTreasureBonus, uint32 _negativeTreasureBonus) = _getCorruptionEffects(_corruptionBalance);

        return appStorage.masterOfInflation.tryMintFromPool(MintFromPoolParams(
            appStorage.tierToPoolId[getTierForFragmentId(_treasureFragmentId)],
            1,
            // Odds boost is out of 256, but masterOfInflation expected out of 100,000
            uint32((_oddsBoost * 100000) / 256) + _positiveTreasureBonus,
            _treasureFragmentId,
            _randomNumber,
            _owner,
            _negativeTreasureBonus
        ));
    }

    function _mintHitReward(
        LibAdvancedQuestingDiamond.ZoneRewardOption storage _zoneRewardOption,
        uint256 _randomNumber,
        address _owner)
    private
    returns(AdvancedQuestReward memory _earnedReward)
    {
        if(_zoneRewardOption.consumableId > 0 && _zoneRewardOption.consumableAmount > 0) {
            _earnedReward.consumableId = _zoneRewardOption.consumableId;
            _earnedReward.consumableAmount = _zoneRewardOption.consumableAmount;

            appStorage.consumable.mint(
                _owner,
                _zoneRewardOption.consumableId,
                _zoneRewardOption.consumableAmount);
        }

        if(_zoneRewardOption.treasureFragmentId > 0) {
            _earnedReward.treasureFragmentId = _zoneRewardOption.treasureFragmentId;

            appStorage.treasureFragment.mint(
                _owner,
                _zoneRewardOption.treasureFragmentId,
                1);
        }

        if(_zoneRewardOption.treasureTier > 0) {
            uint256 _treasureId = appStorage.treasureMetadataStore.getRandomTreasureForTierAndCategory(
                _zoneRewardOption.treasureTier,
                _zoneRewardOption.treasureCategory,
                _randomNumber);

            _earnedReward.treasureId = _treasureId;

            appStorage.treasure.mint(
                _owner,
                _treasureId,
                1);
        }
    }

    function _pickRewardFromOptions(
        uint256 _randomNumber,
        LibAdvancedQuestingDiamond.ZoneReward storage _zoneReward)
    private
    view
    returns(LibAdvancedQuestingDiamond.ZoneRewardOption storage)
    {
        // Gas optimization. Only run random calculations for rewards with more than 1 option.
        if(_zoneReward.rewardOptions.length == 1) {
            return _zoneReward.rewardOptions[0];
        }

        uint256 _result = _randomNumber % 256;
        uint256 _topRange = 0;

        _randomNumber >>= 8;

        for(uint256 j = 0; j < _zoneReward.rewardOptions.length; j++) {
            LibAdvancedQuestingDiamond.ZoneRewardOption storage _zoneRewardOption = _zoneReward.rewardOptions[j];
            _topRange += _zoneRewardOption.rewardOdds;

            if(_result < _topRange) {
                // Got this reward!
                return _zoneRewardOption;
            }
        }

        revert("Bad odds for zone reward");
    }

    function playTreasureTriad(
        PlayTreasureTriadParams[] calldata _params)
    external
    whenNotPaused
    onlyEOA
    {
        require(_params.length > 0, "Bad array length");
        for(uint256 i = 0; i < _params.length; i++) {
            _playTreasureTriad(_params[i].legionId, _params[i].playerMoves, _params[i].restartQuestIfPossible);
        }
    }

    function _playTreasureTriad(uint256 _legionId, UserMove[] calldata _playerMoves, bool _restartQuestingIfPossible) private {

        bool _usingOldSchema = _isUsingOldSchema(_legionId);
        string memory _zoneName = _activeZoneForLegion(_usingOldSchema, _legionId);

        LegionMetadata memory _legionMetadata = appStorage.legionMetadataStore.metadataForLegion(_legionId);
        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo = appStorage.zoneNameToInfo[_zoneName];

        require(_ownerForLegion(_usingOldSchema, _legionId) == msg.sender, "Legion is not yours");

        uint256 _randomNumber = appStorage.randomizer.revealRandomNumber(_requestIdForLegion(_usingOldSchema, _legionId));

        // Don't check for triad as they will be playing it right now.
        _ensureDoneWithCurrentPart(_legionId, _zoneName, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber, false);

        _validatePlayerHasTreasuresForMoves(_playerMoves, _usingOldSchema, _legionId);

        GameOutcome memory _outcome = appStorage.treasureTriad.generateBoardAndPlayGame(
            _legionId,
            _legionMetadata.legionClass,
            _playerMoves);

        // Timestamp used to verify they have played and to calculate the length of stasis post game.
        if(_usingOldSchema) {
            appStorage.legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.timeTriadWasPlayed = block.timestamp;
            appStorage.legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.corruptedCellsRemainingForCurrentPart = _outcome.numberOfCorruptedCardsLeft;
            appStorage.legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.cardsFlipped = _outcome.numberOfFlippedCards;
        } else {
            appStorage.legionIdToLegionQuestingInfoV2[_legionId].timeTriadWasPlayed = uint120(block.timestamp);
            appStorage.legionIdToLegionQuestingInfoV2[_legionId].corruptedCellsRemainingForCurrentPart = _outcome.numberOfCorruptedCardsLeft;
            appStorage.legionIdToLegionQuestingInfoV2[_legionId].cardsFlipped = _outcome.numberOfFlippedCards;
        }

        emit TreasureTriadPlayed(msg.sender, _legionId, _outcome.playerWon, _outcome.numberOfFlippedCards, _outcome.numberOfCorruptedCardsLeft);

        // If there are any corrupted cards left, they will be stuck in stasis and cannot end now.
        if(_outcome.numberOfCorruptedCardsLeft == 0 || !appStorage.generationToCanHaveStasis[_legionMetadata.legionGeneration]) {
            _endQuestingPostValidation(_legionId, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber, _restartQuestingIfPossible);
        }
    }

    function _validatePlayerHasTreasuresForMoves(
        UserMove[] calldata _playerMoves,
        bool _usingOldSchema,
        uint256 _legionId)
    private
    view
    {
        // Before sending to the treasure triad contract, ensure they have staked the treasures and can play them.
        // The treasure triad contract will handle the game logic, and validating that the player moves are valid.
        require(_playerMoves.length > 0 && _playerMoves.length < 4, "Bad number of treasure triad moves");

        // Worst case, they have 3 different treasures.
        Treasure[] memory _treasures = new Treasure[](_playerMoves.length);
        uint256 _treasureIndex = 0;

        for(uint256 i = 0; i < _playerMoves.length; i++) {
            uint256 _treasureIdForMove = _playerMoves[i].treasureId;

            uint256 _treasureAmountStaked = _getTreasureAmountStaked(_treasureIdForMove, _usingOldSchema, _legionId);

            bool _foundLocalTreasure = false;

            for(uint256 k = 0; k < _treasures.length; k++) {
                if(_treasures[k].id == _treasureIdForMove) {
                    _foundLocalTreasure = true;
                    if(_treasures[k].amount == 0) {
                        revert("Used more treasure than what was staked");
                    } else {
                        _treasures[k].amount--;
                    }
                    break;
                }
            }

            if(!_foundLocalTreasure) {
                _treasures[_treasureIndex] = Treasure(_treasureIdForMove, _treasureAmountStaked - 1);
                _treasureIndex++;
            }
        }
    }

    function _getTreasureAmountStaked(
        uint256 _treasureIdForMove,
        bool _usingOldSchema,
        uint256 _legionId)
    private
    view
    returns(uint256)
    {
        if(_usingOldSchema) {
            require(appStorage.legionIdToLegionQuestingInfoV1[_legionId].treasureIds.contains(_treasureIdForMove),
                "Cannot play treasure that was not staked");

            return appStorage.legionIdToLegionQuestingInfoV1[_legionId].treasureIdToAmount[_treasureIdForMove];
        } else {
            LibAdvancedQuestingDiamond.Treasures memory _treasures = appStorage.legionIdToLegionQuestingInfoV2[_legionId].treasures;

            require(_treasureIdForMove > 0);

            if(_treasures.treasure1Id == _treasureIdForMove) {
                return _treasures.treasure1Amount;
            } else if(_treasures.treasure2Id == _treasureIdForMove) {
                return _treasures.treasure2Amount;
            } else if(_treasures.treasure3Id == _treasureIdForMove) {
                return _treasures.treasure3Amount;
            } else if(_treasures.treasure4Id == _treasureIdForMove) {
                return _treasures.treasure4Amount;
            } else if(_treasures.treasure5Id == _treasureIdForMove) {
                return _treasures.treasure5Amount;
            } else if(_treasures.treasure6Id == _treasureIdForMove) {
                return _treasures.treasure6Amount;
            } else if(_treasures.treasure7Id == _treasureIdForMove) {
                return _treasures.treasure7Amount;
            } else {
                revert("Cannot play treasure that was not staked");
            }
        }
    }

    // Returns the end time for the legion and the number of stasis hit in all the parts of the zone.
    // If the legion is waiting through stasis caused by corrupt cards in treasure triad, the second number will be the number of cards remaining.
    function endTimeForLegion(uint256 _legionId) external view returns(uint256, uint8) {
        LegionMetadata memory _legionMetadata = appStorage.legionMetadataStore.metadataForLegion(_legionId);

        bool _usingOldSchema = _isUsingOldSchema(_legionId);

        uint8 _maxConstellationRank = _maxConstellationRankForLegionAndZone(
            _activeZoneForLegion(_usingOldSchema, _legionId),
            _legionMetadata);

        uint256 _randomNumber = appStorage.randomizer.revealRandomNumber(_requestIdForLegion(_usingOldSchema, _legionId));

        return _endTimeForLegion(_legionId, _usingOldSchema, _activeZoneForLegion(_usingOldSchema, _legionId), _legionMetadata, _maxConstellationRank, _randomNumber);
    }

    function getN(uint64 _poolId) external view returns(uint256) {
        if(appStorage.tierToRecruitPoolId[5] == _poolId) {
            return appStorage.numRecruitsQuesting;
        } else {
            return appStorage.numQuesting;
        }
    }

    function getTierForFragmentId(uint256 _fragmentId) private pure returns(uint8 _tier) {
        _tier = uint8(_fragmentId % 5);

        if(_tier == 0) {
            _tier = 5;
        }
    }
}

struct Treasure {
    uint256 id;
    uint256 amount;
}

struct PlayTreasureTriadParams {
    uint256 legionId;
    UserMove[] playerMoves;
    bool restartQuestIfPossible;
}
