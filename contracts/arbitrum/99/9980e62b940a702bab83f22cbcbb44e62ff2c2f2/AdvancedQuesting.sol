//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdvancedQuestingSettings.sol";

contract AdvancedQuesting is Initializable, AdvancedQuestingSettings {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        AdvancedQuestingSettings.__AdvancedQuestingSettings_init();
    }

    function startAdvancedQuesting(StartQuestParams[] calldata _params)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(_params.length > 0, "No start quest params given");

        for(uint256 i = 0; i < _params.length; i++) {
            _startAdvancedQuesting(_params[i]);
        }
    }

    function _startAdvancedQuesting(StartQuestParams calldata _startQuestParams) private {
        uint256 _legionId = _startQuestParams.legionId;

        require(!isLegionQuesting(_legionId), "Legion is already questing");
        require(isValidZone(_startQuestParams.zoneName), "Invalid zone");

        uint256 _numberOfParts = zoneNameToInfo[_startQuestParams.zoneName].parts.length;
        require(_startQuestParams.advanceToPart > 0 && _startQuestParams.advanceToPart <= _numberOfParts,
            "Invalid advance to part");

        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);

        require(_legionMetadata.legionGeneration != LegionGeneration.RECRUIT, "Recruit cannot advanced quest");

        bool _willPlayTreasureTriad = false;

        // Need to check that they have the correct level to advance through the given parts of the quest.
        for(uint256 i = 0; i < _startQuestParams.advanceToPart; i++) {
            uint8 _levelRequirement = zoneNameToInfo[_startQuestParams.zoneName].parts[i].questingLevelRequirement;

            require(_legionMetadata.questLevel >= _levelRequirement, "Legion not high enough questing level");

            bool _treasureTriadOnThisPart = zoneNameToInfo[_startQuestParams.zoneName].parts[i].playTreasureTriad;

            _willPlayTreasureTriad = _willPlayTreasureTriad || _treasureTriadOnThisPart;

            // Also, if a part has a treasure triad game and it is not the last part, they cannot auto advance past it.
            if(i < _startQuestParams.advanceToPart - 1 && _treasureTriadOnThisPart) {

                revert("Cannot advanced past a part that requires treasure triad");
            }
        }

        require(_startQuestParams.treasureIds.length == _startQuestParams.treasureAmounts.length,
            "Bad treasure lengths");
        require(!_willPlayTreasureTriad || _startQuestParams.treasureIds.length > 0,
            "Need treasure to play treasure triad");

        uint256 _totalTreasureAmounts = 0;
        uint8 _maxConstellationRank = _maxConstellationRankForLegionAndZone(_startQuestParams.zoneName, _legionMetadata);

        for(uint256 i = 0; i < _startQuestParams.treasureIds.length; i++) {
            require(_startQuestParams.treasureIds[i] > 0 && _startQuestParams.treasureAmounts[i] > 0,
                "Bad treasure id or amount");

            _totalTreasureAmounts += _startQuestParams.treasureAmounts[i];

            require(_totalTreasureAmounts <= _maxConstellationRank, "Too many treasures for constellation rank");
        }

        uint256 _requestId = randomizer.requestRandomNumber();

        legionIdToLegionQuestingInfoV2[_legionId].startTime = uint120(block.timestamp);
        legionIdToLegionQuestingInfoV2[_legionId].requestId = uint80(_requestId);
        legionIdToLegionQuestingInfoV2[_legionId].zoneName = _startQuestParams.zoneName;
        legionIdToLegionQuestingInfoV2[_legionId].owner = msg.sender;
        legionIdToLegionQuestingInfoV2[_legionId].advanceToPart = _startQuestParams.advanceToPart;
        legionIdToLegionQuestingInfoV2[_legionId].currentPart = 0;
        delete legionIdToLegionQuestingInfoV2[_legionId].timeTriadWasPlayed;
        delete legionIdToLegionQuestingInfoV2[_legionId].corruptedCellsRemainingForCurrentPart;
        delete legionIdToLegionQuestingInfoV2[_legionId].cardsFlipped;

        _saveStakedTreasures(_startQuestParams);

        // Transfer legion and treasure to this contract.
        legion.adminSafeTransferFrom(msg.sender, address(this), _legionId);

        if(_startQuestParams.treasureIds.length > 0) {
            treasure.safeBatchTransferFrom(
                msg.sender,
                address(this),
                _startQuestParams.treasureIds,
                _startQuestParams.treasureAmounts,
                "");
        }

        emit AdvancedQuestStarted(
            msg.sender,
            _requestId,
            _startQuestParams);
    }

    function _saveStakedTreasures(
        StartQuestParams calldata _startQuestParams)
    private
    {
        Treasures memory _treasures;

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

        legionIdToLegionQuestingInfoV2[_startQuestParams.legionId].treasures = _treasures;
    }

    function continueAdvancedQuesting(uint256[] calldata _legionIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_legionIds)
    {
        for(uint256 i = 0; i < _legionIds.length; i++) {
            _continueAdvancedQuesting(_legionIds[i]);
        }
    }

    function _continueAdvancedQuesting(uint256 _legionId) private {
        bool _usingOldSchema = _isUsingOldSchema(_legionId);

        string memory _zoneName = _activeZoneForLegion(_usingOldSchema, _legionId);

        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);
        ZoneInfo storage _zoneInfo = zoneNameToInfo[_zoneName];

        require(_ownerForLegion(_usingOldSchema, _legionId) == msg.sender, "Legion is not yours");

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestIdForLegion(_usingOldSchema, _legionId));

        _ensureDoneWithCurrentPart(_legionId, _zoneName, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber, true);

        uint8 _advanceToPart = _advanceToPartForLegion(_usingOldSchema, _legionId);

        // Ensure we are not continuing too far.
        require(_advanceToPart + 1 <= _zoneInfo.parts.length, "Already at last part");

        // Check if player can even advance to part.
        // Using advancedToPart as index because it is the index of the next part.
        require(_legionMetadata.questLevel >= _zoneInfo.parts[_advanceToPart].questingLevelRequirement,
            "Legion not high enough questing level");

        // If the next part has a triad requirement, must have treasure staked still.
        require(!_zoneInfo.parts[_advanceToPart].playTreasureTriad
            || _hasTreasuresStakedForLegion(_usingOldSchema, _legionId),
            "No treasure staked for legion");

        // Need new number for stasis role + potentially treasure triad.
        uint256 _requestId = randomizer.requestRandomNumber();

        if(_usingOldSchema) {
            legionIdToLegionQuestingInfoV1[_legionId].startTime = block.timestamp;
            legionIdToLegionQuestingInfoV1[_legionId].currentPart = _advanceToPart;
            legionIdToLegionQuestingInfoV1[_legionId].advanceToPart++;
            delete legionIdToLegionQuestingInfoV1[_legionId];
            legionIdToLegionQuestingInfoV1[_legionId].requestId = _requestId;
        } else {
            legionIdToLegionQuestingInfoV2[_legionId].startTime = uint120(block.timestamp);
            legionIdToLegionQuestingInfoV2[_legionId].currentPart = _advanceToPart;
            legionIdToLegionQuestingInfoV2[_legionId].advanceToPart++;
            delete legionIdToLegionQuestingInfoV2[_legionId].timeTriadWasPlayed;
            delete legionIdToLegionQuestingInfoV2[_legionId].corruptedCellsRemainingForCurrentPart;
            delete legionIdToLegionQuestingInfoV2[_legionId].cardsFlipped;
            legionIdToLegionQuestingInfoV2[_legionId].requestId = uint80(_requestId);
        }

        emit AdvancedQuestContinued(msg.sender, _legionId, _requestId, _advanceToPart + 1);
    }

    // Ends questing at the current part. Must have played triad if triad is required on current part.
    function endQuesting(
        uint256[] calldata _legionIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_legionIds)
    {
        for(uint256 i = 0; i < _legionIds.length; i++) {
            _endQuesting(_legionIds[i]);
        }
    }

    function _endQuesting(uint256 _legionId) private {
        bool _usingOldSchema = _isUsingOldSchema(_legionId);

        string memory _zoneName = _activeZoneForLegion(_usingOldSchema, _legionId);

        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);
        ZoneInfo storage _zoneInfo = zoneNameToInfo[_zoneName];

        require(_ownerForLegion(_usingOldSchema, _legionId) == msg.sender, "Legion is not yours");

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestIdForLegion(_usingOldSchema, _legionId));

        _ensureDoneWithCurrentPart(_legionId, _zoneName, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber, true);

        _endQuestingPostValidation(_legionId, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber);
    }

    function _endQuestingPostValidation(
        uint256 _legionId,
        bool _usingOldSchema,
        LegionMetadata memory _legionMetadata,
        ZoneInfo storage _zoneInfo,
        uint256 _randomNumber)
    private
    {
        questing.processQPGainAndLevelUp(_legionId, _legionMetadata.questLevel);

        AdvancedQuestReward[] memory _earnedRewards = _distributeRewards(_legionId, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber);

        // Only need to delete the start time to save on gas. Acts as a flag if the legion is questing.
        // When startQuesting is called all LegionQuestingInfo fields will be overridden.
        if(_usingOldSchema) {
            delete legionIdToLegionQuestingInfoV1[_legionId].startTime;
        } else {
            delete legionIdToLegionQuestingInfoV2[_legionId].startTime;
        }

        // Send back legion and treasure
        legion.adminSafeTransferFrom(address(this), msg.sender, _legionId);

        _unstakeTreasures(_legionId, _usingOldSchema);

        emit AdvancedQuestEnded(msg.sender, _legionId, _earnedRewards);
    }

    function _unstakeTreasures(
        uint256 _legionId,
        bool _usingOldSchema)
    private {

        uint256[] memory _treasureIds;
        uint256[] memory _treasureAmounts;

        if(_usingOldSchema) {
            _treasureIds = legionIdToLegionQuestingInfoV1[_legionId].treasureIds.values();
            _treasureAmounts = new uint256[](_treasureIds.length);

            for(uint256 i = 0; i < _treasureIds.length; i++) {
                // No longer need to remove these from the mapping, as it is the old schema.
                // _legionQuestingInfo.treasureIds.remove(_treasureIds[i]);
                _treasureAmounts[i] = legionIdToLegionQuestingInfoV1[_legionId].treasureIdToAmount[_treasureIds[i]];
            }
        } else {
            Treasures memory _treasures = legionIdToLegionQuestingInfoV2[_legionId].treasures;
            uint8 _numberOfTreasureTypes = _treasures.numberOfTypesOfTreasures;
            _treasureIds = new uint256[](_numberOfTreasureTypes);
            _treasureAmounts = new uint256[](_numberOfTreasureTypes);
            if(_numberOfTreasureTypes > 0) {
                _treasureIds[0] = _treasures.treasure1Id;
                _treasureAmounts[0] = _treasures.treasure1Amount;
            }
            if(_numberOfTreasureTypes > 1) {
                _treasureIds[1] = _treasures.treasure2Id;
                _treasureAmounts[1] = _treasures.treasure2Amount;
            }
            if(_numberOfTreasureTypes > 2) {
                _treasureIds[2] = _treasures.treasure3Id;
                _treasureAmounts[2] = _treasures.treasure3Amount;
            }
            if(_numberOfTreasureTypes > 3) {
                _treasureIds[3] = _treasures.treasure4Id;
                _treasureAmounts[3] = _treasures.treasure4Amount;
            }
            if(_numberOfTreasureTypes > 4) {
                _treasureIds[4] = _treasures.treasure5Id;
                _treasureAmounts[4] = _treasures.treasure5Amount;
            }
            if(_numberOfTreasureTypes > 5) {
                _treasureIds[5] = _treasures.treasure6Id;
                _treasureAmounts[5] = _treasures.treasure6Amount;
            }
            if(_numberOfTreasureTypes > 6) {
                _treasureIds[6] = _treasures.treasure7Id;
                _treasureAmounts[6] = _treasures.treasure7Amount;
            }
        }

        if(_treasureIds.length > 0) {
            treasure.safeBatchTransferFrom(
                address(this),
                msg.sender,
                _treasureIds,
                _treasureAmounts,
                "");
        }
    }

    function _distributeRewards(
        uint256 _legionId,
        bool _usingOldSchema,
        LegionMetadata memory _legionMetadata,
        ZoneInfo storage _zoneInfo,
        uint256 _randomNumber)
    private
    returns(AdvancedQuestReward[] memory)
    {
        // Gain Rewards!
        ZonePart storage _endingPart = _zoneInfo.parts[_advanceToPartForLegion(_usingOldSchema, _legionId) - 1];

        // The returned random number was used for stasis calculations. Scramble the number with a constant.
        _randomNumber = uint256(keccak256(abi.encode(_randomNumber,
            17647295972771752179227871979083739911846583376458796885201641052640283607576)));

        uint256 _legionGeneration = uint256(_legionMetadata.legionGeneration);
        uint256 _legionRarity = uint256(_legionMetadata.legionRarity);

        AdvancedQuestReward[] memory _earnedRewards = new AdvancedQuestReward[](_endingPart.rewards.length);

        uint8 _cardsFlipped = _cardsFlippedForLegion(_usingOldSchema, _legionId);

        for(uint256 i = 0; i < _endingPart.rewards.length; i++) {
            ZoneReward storage _reward = _endingPart.rewards[i];
            uint256 _odds = _reward.baseRateRewardOdds
                + _reward.generationToRarityToBoost[_legionGeneration][_legionRarity]
                + (_reward.boostPerFlippedCard * _cardsFlipped);

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
                ZoneRewardOption storage _zoneRewardOption = _pickRewardFromOptions(_randomNumber, _reward);

                _earnedRewards[i] = _mintHitReward(_zoneRewardOption, _randomNumber);

                _randomNumber >>= 8;
            }
        }

        return _earnedRewards;
    }

    function _mintHitReward(
        ZoneRewardOption storage _zoneRewardOption,
        uint256 _randomNumber)
    private
    returns(AdvancedQuestReward memory _earnedReward)
    {
        if(_zoneRewardOption.consumableId > 0 && _zoneRewardOption.consumableAmount > 0) {
            _earnedReward.consumableId = _zoneRewardOption.consumableId;
            _earnedReward.consumableAmount = _zoneRewardOption.consumableAmount;

            consumable.mint(
                msg.sender,
                _zoneRewardOption.consumableId,
                _zoneRewardOption.consumableAmount);
        }

        if(_zoneRewardOption.treasureFragmentId > 0) {
            _earnedReward.treasureFragmentId = _zoneRewardOption.treasureFragmentId;

            treasureFragment.mint(
                msg.sender,
                _zoneRewardOption.treasureFragmentId,
                1);
        }

        if(_zoneRewardOption.treasureTier > 0) {
            uint256 _treasureId = treasureMetadataStore.getRandomTreasureForTierAndCategory(
                _zoneRewardOption.treasureTier,
                _zoneRewardOption.treasureCategory,
                _randomNumber);

            _earnedReward.treasureId = _treasureId;

            treasure.mint(
                msg.sender,
                _treasureId,
                1);
        }
    }

    function _pickRewardFromOptions(
        uint256 _randomNumber,
        ZoneReward storage _zoneReward)
    private
    view
    returns(ZoneRewardOption storage)
    {
        // Gas optimization. Only run random calculations for rewards with more than 1 option.
        if(_zoneReward.rewardOptions.length == 1) {
            return _zoneReward.rewardOptions[0];
        }

        uint256 _result = _randomNumber % 256;
        uint256 _topRange = 0;

        _randomNumber >>= 8;

        for(uint256 j = 0; j < _zoneReward.rewardOptions.length; j++) {
            ZoneRewardOption storage _zoneRewardOption = _zoneReward.rewardOptions[j];
            _topRange += _zoneRewardOption.rewardOdds;

            if(_result < _topRange) {
                // Got this reward!
                return _zoneRewardOption;
            }
        }

        revert("Bad odds for zone reward");
    }

    function playTreasureTriad(
        uint256[] calldata _legionIds,
        UserMove[][] calldata _playerMoves,
        bool[] calldata _endQuestingAfterPlayingIfPossible)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_legionIds)
    {
        require(_legionIds.length == _playerMoves.length && _legionIds.length == _endQuestingAfterPlayingIfPossible.length, "Bad array lengths for play");
        for(uint256 i = 0; i < _legionIds.length; i++) {
            _playTreasureTriad(_legionIds[i], _playerMoves[i], _endQuestingAfterPlayingIfPossible[i]);
        }
    }

    function _playTreasureTriad(uint256 _legionId, UserMove[] calldata _playerMoves, bool _endQuestingIfPossible) private {

        bool _usingOldSchema = _isUsingOldSchema(_legionId);
        string memory _zoneName = _activeZoneForLegion(_usingOldSchema, _legionId);

        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);
        ZoneInfo storage _zoneInfo = zoneNameToInfo[_zoneName];

        require(_ownerForLegion(_usingOldSchema, _legionId) == msg.sender, "Legion is not yours");

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestIdForLegion(_usingOldSchema, _legionId));

        // Don't check for triad as they will be playing it right now.
        _ensureDoneWithCurrentPart(_legionId, _zoneName, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber, false);

        _validatePlayerHasTreasuresForMoves(_playerMoves, _usingOldSchema, _legionId);

        GameOutcome memory _outcome = treasureTriad.generateBoardAndPlayGame(
            _randomNumber,
            _legionMetadata.legionClass,
            _playerMoves);

        // Timestamp used to verify they have played and to calculate the length of stasis post game.
        if(_usingOldSchema) {
            legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.timeTriadWasPlayed = block.timestamp;
            legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.corruptedCellsRemainingForCurrentPart = _outcome.numberOfCorruptedCardsLeft;
            legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.cardsFlipped = _outcome.numberOfFlippedCards;
        } else {
            legionIdToLegionQuestingInfoV2[_legionId].timeTriadWasPlayed = uint120(block.timestamp);
            legionIdToLegionQuestingInfoV2[_legionId].corruptedCellsRemainingForCurrentPart = _outcome.numberOfCorruptedCardsLeft;
            legionIdToLegionQuestingInfoV2[_legionId].cardsFlipped = _outcome.numberOfFlippedCards;
        }

        emit TreasureTriadPlayed(msg.sender, _legionId, _outcome.playerWon, _outcome.numberOfFlippedCards, _outcome.numberOfCorruptedCardsLeft);

        // If there are any corrupted cards left, they will be stuck in stasis and cannot end now.
        if(_endQuestingIfPossible && _outcome.numberOfCorruptedCardsLeft == 0) {
            _endQuestingPostValidation(_legionId, _usingOldSchema, _legionMetadata, _zoneInfo, _randomNumber);
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
            require(legionIdToLegionQuestingInfoV1[_legionId].treasureIds.contains(_treasureIdForMove),
                "Cannot play treasure that was not staked");

            return legionIdToLegionQuestingInfoV1[_legionId].treasureIdToAmount[_treasureIdForMove];
        } else {
            Treasures memory _treasures = legionIdToLegionQuestingInfoV2[_legionId].treasures;

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

    // Ensures the legion is done with the current part they are on.
    // This includes checking the end time and making sure they played treasure triad.
    function _ensureDoneWithCurrentPart(
        uint256 _legionId,
        string memory _zoneName,
        bool _usingOldSchema,
        LegionMetadata memory _legionMetadata,
        ZoneInfo storage _zoneInfo,
        uint256 _randomNumber,
        bool _checkPlayedTriad)
    private
    view
    {
        uint8 _maxConstellationRank = _maxConstellationRankForLegionAndZone(
            _zoneName,
            _legionMetadata);

        // Handles checking if the legion is questing or not. Will revert if not.
        // Handles checking if stasis random is ready. Will revert if not.
        (uint256 _endTime,) = _endTimeForLegion(_legionId, _usingOldSchema, _zoneName, _legionMetadata, _maxConstellationRank, _randomNumber);
        require(block.timestamp >= _endTime, "Legion has not finished this part of the zone yet");

        // Triad played check. Only need to check the last part as _startAdvancedQuesting would have reverted
        // if they tried to skip past a triad played check.
        if(_checkPlayedTriad
            && _zoneInfo.parts[_advanceToPartForLegion(_usingOldSchema, _legionId) - 1].playTreasureTriad
            && _triadPlayTimeForLegion(_usingOldSchema, _legionId) == 0) {

            revert("Has not played treasure triad for current part");
        }
    }

    function isLegionQuesting(uint256 _legionId) public view returns(bool) {
        return legionIdToLegionQuestingInfoV1[_legionId].startTime > 0
            || legionIdToLegionQuestingInfoV2[_legionId].startTime > 0;
    }

    function _activeZoneForLegion(bool _useOldSchema, uint256 _legionId) private view returns(string storage) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].zoneName
            : legionIdToLegionQuestingInfoV2[_legionId].zoneName;
    }

    function _ownerForLegion(bool _useOldSchema, uint256 _legionId) private view returns(address) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].owner
            : legionIdToLegionQuestingInfoV2[_legionId].owner;
    }

    function _requestIdForLegion(bool _useOldSchema, uint256 _legionId) private view returns(uint256) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].requestId
            : legionIdToLegionQuestingInfoV2[_legionId].requestId;
    }

    function _advanceToPartForLegion(bool _useOldSchema, uint256 _legionId) private view returns(uint8) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].advanceToPart
            : legionIdToLegionQuestingInfoV2[_legionId].advanceToPart;
    }

    function _currentPartForLegion(bool _useOldSchema, uint256 _legionId) private view returns(uint8) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].currentPart
            : legionIdToLegionQuestingInfoV2[_legionId].currentPart;
    }

    function _hasTreasuresStakedForLegion(bool _useOldSchema, uint256 _legionId) private view returns(bool) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].treasureIds.length() > 0
            : legionIdToLegionQuestingInfoV2[_legionId].treasures.treasure1Id > 0;
    }

    function _triadPlayTimeForLegion(bool _useOldSchema, uint256 _legionId) private view returns(uint256) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.timeTriadWasPlayed
            : legionIdToLegionQuestingInfoV2[_legionId].timeTriadWasPlayed;
    }

    function _cardsFlippedForLegion(bool _useOldSchema, uint256 _legionId) private view returns(uint8) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.cardsFlipped
            : legionIdToLegionQuestingInfoV2[_legionId].cardsFlipped;
    }

    function _corruptedCellsRemainingForLegion(bool _useOldSchema, uint256 _legionId) private view returns(uint8) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.corruptedCellsRemainingForCurrentPart
            : legionIdToLegionQuestingInfoV2[_legionId].corruptedCellsRemainingForCurrentPart;
    }

    function _startTimeForLegion(bool _useOldSchema, uint256 _legionId) private view returns(uint256) {
        return _useOldSchema
            ? legionIdToLegionQuestingInfoV1[_legionId].startTime
            : legionIdToLegionQuestingInfoV2[_legionId].startTime;
    }

    function _isUsingOldSchema(uint256 _legionId) private view returns(bool) {
        return legionIdToLegionQuestingInfoV1[_legionId].startTime > 0;
    }

    // Returns the end time for the legion and the number of stasis hit in all the parts of the zone.
    // If the legion is waiting through stasis caused by corrupt cards in treasure triad, the second number will be the number of cards remaining.
    function endTimeForLegion(uint256 _legionId) external view returns(uint256, uint8) {
        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);

        bool _usingOldSchema = _isUsingOldSchema(_legionId);

        uint8 _maxConstellationRank = _maxConstellationRankForLegionAndZone(
            _activeZoneForLegion(_usingOldSchema, _legionId),
            _legionMetadata);

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestIdForLegion(_usingOldSchema, _legionId));

        return _endTimeForLegion(_legionId, _usingOldSchema, _activeZoneForLegion(_usingOldSchema, _legionId), _legionMetadata, _maxConstellationRank, _randomNumber);
    }

    function _endTimeForLegion(
        uint256 _legionId,
        bool _usingOldSchema,
        string memory _zoneName,
        LegionMetadata memory _legionMetadata,
        uint8 _maxConstellationRank,
        uint256 _randomNumber)
    private
    view
    returns(uint256 _endTime, uint8 _stasisHitCount)
    {
        require(isLegionQuesting(_legionId), "Legion is not questing");

        uint256 _triadPlayTime = _triadPlayTimeForLegion(_usingOldSchema, _legionId);
        uint8 _corruptCellsRemaining = _corruptedCellsRemainingForLegion(_usingOldSchema, _legionId);
        uint8 _advanceToPart = _advanceToPartForLegion(_usingOldSchema, _legionId);
        uint8 _currentPart = _currentPartForLegion(_usingOldSchema, _legionId);

        // If this part requires treasure triad, and the user has already played it for this part,
        // AND the use had a corrupted card... the end time will be based on that stasis.
        if(zoneNameToInfo[_zoneName].parts[_advanceToPart - 1].playTreasureTriad
            && _triadPlayTime > 0
            && _corruptCellsRemaining > 0)
        {
            return (_triadPlayTime + (_corruptCellsRemaining * stasisLengthForCorruptedCard), _corruptCellsRemaining);
        }

        uint256 _totalLength;

        (_totalLength, _stasisHitCount) = _calculateStasis(
            zoneNameToInfo[_zoneName],
            _legionMetadata,
            _randomNumber,
            _maxConstellationRank,
            _currentPart,
            _advanceToPart
        );

        _endTime = _startTimeForLegion(_usingOldSchema, _legionId) + _totalLength;
    }

    function _calculateStasis(
        ZoneInfo storage _zoneInfo,
        LegionMetadata memory _legionMetadata,
        uint256 _randomNumber,
        uint8 _maxConstellationRank,
        uint8 _currentPart,
        uint8 _advanceToPart)
    private
    view
    returns(uint256 _totalLength, uint8 _stasisHitCount)
    {

        uint8 _baseRateReduction = maxConstellationRankToReductionInStasis[_maxConstellationRank];

        // For example, assume currentPart is 0 and they are advancing to part 1.
        // We will go through this for loop once. The first time, i = 0, which is also
        // the index of the parts array in the ZoneInfo object.
        for(uint256 i = _currentPart; i < _advanceToPart; i++) {
            _totalLength += _zoneInfo.parts[i].zonePartLength;

            if(generationToCanHaveStasis[_legionMetadata.legionGeneration]) {
                uint8 _baseRate = _zoneInfo.parts[i].stasisBaseRate;

                // If not greater than, no chance of stasis!
                if(_baseRate > _baseRateReduction) {
                    if(_randomNumber % 256 < _baseRate - _baseRateReduction) {
                        _stasisHitCount++;
                        _totalLength += _zoneInfo.parts[i].stasisLength;
                    }

                    _randomNumber >>= 8;
                }
            }
        }
    }

    function _maxConstellationRankForLegionAndZone(
        string memory _zoneName,
        LegionMetadata memory _legionMetadata)
    private
    view
    returns(uint8)
    {
        uint8 _rankConstellation1 = _legionMetadata.constellationRanks[uint256(zoneNameToInfo[_zoneName].constellation1)];
        uint8 _rankConstellation2 = _legionMetadata.constellationRanks[uint256(zoneNameToInfo[_zoneName].constellation2)];
        if(_rankConstellation1 > _rankConstellation2) {
            return _rankConstellation1;
        } else {
            return _rankConstellation2;
        }
    }
}

struct Treasure {
    uint256 id;
    uint256 amount;
}
