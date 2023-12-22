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

        uint256 _numberOfParts = numberOfPartsInZone(_startQuestParams.zoneName);
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

        legionIdToLegionQuestingInfo[_legionId].startTime = block.timestamp;
        legionIdToLegionQuestingInfo[_legionId].requestId = _requestId;
        legionIdToLegionQuestingInfo[_legionId].zoneName = _startQuestParams.zoneName;
        legionIdToLegionQuestingInfo[_legionId].owner = msg.sender;
        legionIdToLegionQuestingInfo[_legionId].advanceToPart = _startQuestParams.advanceToPart;
        legionIdToLegionQuestingInfo[_legionId].currentPart = 0;
        delete  legionIdToLegionQuestingInfo[_legionId].triadOutcome;
        for(uint256 i = 0; i < _startQuestParams.treasureIds.length; i++) {
            uint256 _treasureId = _startQuestParams.treasureIds[i];
            require(!legionIdToLegionQuestingInfo[_legionId].treasureIds.contains(_treasureId), "Duplicate treasure id in array");
            legionIdToLegionQuestingInfo[_legionId].treasureIds.add(_treasureId);
            legionIdToLegionQuestingInfo[_legionId].treasureIdToAmount[_treasureId] = _startQuestParams.treasureAmounts[i];
        }

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
        LegionQuestingInfo storage _legionQuestingInfo = legionIdToLegionQuestingInfo[_legionId];
        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);
        ZoneInfo storage _zoneInfo = zoneNameToInfo[_legionQuestingInfo.zoneName];

        require(_legionQuestingInfo.owner == msg.sender, "Legion is not yours");

        uint256 _randomNumber = randomizer.revealRandomNumber(legionIdToLegionQuestingInfo[_legionId].requestId);

        _ensureDoneWithCurrentPart(_legionId, _legionQuestingInfo, _legionMetadata, _zoneInfo, _randomNumber, true);

        // Ensure we are not continuing too far.
        require(_legionQuestingInfo.advanceToPart + 1 <= _zoneInfo.parts.length, "Already at last part");

        // Check if player can even advance to part.
        // Using advancedToPart as index because it is the index of the next part.
        require(_legionMetadata.questLevel >= _zoneInfo.parts[_legionQuestingInfo.advanceToPart].questingLevelRequirement,
            "Legion not high enough questing level");

        // If the next part has a triad requirement, must have treasure staked still.
        require(!_zoneInfo.parts[_legionQuestingInfo.advanceToPart].playTreasureTriad
            || _legionQuestingInfo.treasureIds.length() > 0,
            "No treasure staked for legion");

        // Need new number for stasis role + potentially treasure triad.
        uint256 _requestId = randomizer.requestRandomNumber();

        _legionQuestingInfo.startTime = block.timestamp;
        _legionQuestingInfo.currentPart = _legionQuestingInfo.advanceToPart;
        _legionQuestingInfo.advanceToPart++;
        delete _legionQuestingInfo.triadOutcome;
        _legionQuestingInfo.requestId = _requestId;

        emit AdvancedQuestContinued(msg.sender, _legionId, _requestId, _legionQuestingInfo.advanceToPart);
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
        LegionQuestingInfo storage _legionQuestingInfo = legionIdToLegionQuestingInfo[_legionId];
        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);
        ZoneInfo storage _zoneInfo = zoneNameToInfo[_legionQuestingInfo.zoneName];

        require(_legionQuestingInfo.owner == msg.sender, "Legion is not yours");

        uint256 _randomNumber = randomizer.revealRandomNumber(legionIdToLegionQuestingInfo[_legionId].requestId);

        _ensureDoneWithCurrentPart(_legionId, _legionQuestingInfo, _legionMetadata, _zoneInfo, _randomNumber, true);

        _endQuestingPostValidation(_legionId, _legionQuestingInfo, _legionMetadata, _zoneInfo, _randomNumber);
    }

    function _endQuestingPostValidation(
        uint256 _legionId,
        LegionQuestingInfo storage _legionQuestingInfo,
        LegionMetadata memory _legionMetadata,
        ZoneInfo storage _zoneInfo,
        uint256 _randomNumber)
    private
    {
        questing.processQPGainAndLevelUp(_legionId, _legionMetadata.questLevel);

        AdvancedQuestReward[] memory _earnedRewards = _distributeRewards(_legionQuestingInfo, _legionMetadata, _zoneInfo, _randomNumber);

        // Only need to delete the start time to save on gas. Acts as a flag if the legion is questing.
        // When startQuesting is called all LegionQuestingInfo fields will be overridden.
        delete _legionQuestingInfo.startTime;

        // Send back legion and treasure
        legion.adminSafeTransferFrom(address(this), msg.sender, _legionId);

        uint256[] memory _treasureIds = _legionQuestingInfo.treasureIds.values();
        uint256[] memory _treasureAmounts = new uint256[](_treasureIds.length);

        for(uint256 i = 0; i < _treasureIds.length; i++) {
            _legionQuestingInfo.treasureIds.remove(_treasureIds[i]);
            _treasureAmounts[i] = _legionQuestingInfo.treasureIdToAmount[_treasureIds[i]];
        }

        if(_treasureIds.length > 0) {
            treasure.safeBatchTransferFrom(
                address(this),
                msg.sender,
                _treasureIds,
                _treasureAmounts,
                "");
        }

        emit AdvancedQuestEnded(msg.sender, _legionId, _earnedRewards);
    }

    function _distributeRewards(
        LegionQuestingInfo storage _legionQuestingInfo,
        LegionMetadata memory _legionMetadata,
        ZoneInfo storage _zoneInfo,
        uint256 _randomNumber)
    private
    returns(AdvancedQuestReward[] memory)
    {
        // Gain Rewards!
        ZonePart storage _endingPart = _zoneInfo.parts[_legionQuestingInfo.advanceToPart - 1];

        // The returned random number was used for stasis calculations. Scramble the number with a constant.
        _randomNumber = uint256(keccak256(abi.encode(_randomNumber,
            17647295972771752179227871979083739911846583376458796885201641052640283607576)));

        uint256 _legionGeneration = uint256(_legionMetadata.legionGeneration);
        uint256 _legionRarity = uint256(_legionMetadata.legionRarity);

        AdvancedQuestReward[] memory _earnedRewards = new AdvancedQuestReward[](_endingPart.rewards.length);

        for(uint256 i = 0; i < _endingPart.rewards.length; i++) {
            ZoneReward storage _reward = _endingPart.rewards[i];
            uint256 _odds = _reward.baseRateRewardOdds
                + _reward.generationToRarityToBoost[_legionGeneration][_legionRarity]
                + (_reward.boostPerFlippedCard * _legionQuestingInfo.triadOutcome.cardsFlipped);

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

                if(_zoneRewardOption.consumableId > 0 && _zoneRewardOption.consumableAmount > 0) {
                    _earnedRewards[i].consumableId = _zoneRewardOption.consumableId;
                    _earnedRewards[i].consumableAmount = _zoneRewardOption.consumableAmount;

                    consumable.mint(
                        msg.sender,
                        _zoneRewardOption.consumableId,
                        _zoneRewardOption.consumableAmount);
                }

                if(_zoneRewardOption.treasureFragmentId > 0) {
                    _earnedRewards[i].treasureFragmentId = _zoneRewardOption.treasureFragmentId;

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

                    _earnedRewards[i].treasureId = _treasureId;

                    treasure.mint(
                        msg.sender,
                        _treasureId,
                        1);
                }

                _randomNumber >>= 8;
            }
        }

        return _earnedRewards;
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
        LegionQuestingInfo storage _legionQuestingInfo = legionIdToLegionQuestingInfo[_legionId];
        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);
        ZoneInfo storage _zoneInfo = zoneNameToInfo[_legionQuestingInfo.zoneName];

        require(_legionQuestingInfo.owner == msg.sender, "Legion is not yours");

        uint256 _randomNumber = randomizer.revealRandomNumber(legionIdToLegionQuestingInfo[_legionId].requestId);

        // Don't check for triad as they will be playing it right now.
        _ensureDoneWithCurrentPart(_legionId, _legionQuestingInfo, _legionMetadata, _zoneInfo, _randomNumber, false);

        _validatePlayerHasTreasuresForMoves(_playerMoves, _legionQuestingInfo);

        GameOutcome memory _outcome = treasureTriad.generateBoardAndPlayGame(
            _randomNumber,
            _legionMetadata.legionClass,
            _playerMoves);

        // Timestamp used to verify they have played and to calculate the length of stasis post game.
        _legionQuestingInfo.triadOutcome.timeTriadWasPlayed = block.timestamp;
        _legionQuestingInfo.triadOutcome.corruptedCellsRemainingForCurrentPart = _outcome.numberOfCorruptedCardsLeft;
        _legionQuestingInfo.triadOutcome.cardsFlipped = _outcome.numberOfFlippedCards;

        emit TreasureTriadPlayed(msg.sender, _legionId, _outcome.playerWon, _outcome.numberOfFlippedCards, _outcome.numberOfCorruptedCardsLeft);

        // If there are any corrupted cards left, they will be stuck in stasis and cannot end now.
        if(_endQuestingIfPossible && _outcome.numberOfCorruptedCardsLeft == 0) {
            _endQuestingPostValidation(_legionId, _legionQuestingInfo, _legionMetadata, _zoneInfo, _randomNumber);
        }
    }

    function _validatePlayerHasTreasuresForMoves(UserMove[] calldata _playerMoves, LegionQuestingInfo storage _legionQuestingInfo) private view {
        // Before sending to the treasure triad contract, ensure they have staked the treasures and can play them.
        // The treasure triad contract will handle the game logic, and validating that the player moves are valid.
        require(_playerMoves.length > 0 && _playerMoves.length < 4, "Bad number of treasure triad moves");

        // Worst case, they have 3 different treasures.
        Treasure[] memory _treasures = new Treasure[](_playerMoves.length);
        uint256 _treasureIndex = 0;

        for(uint256 i = 0; i < _playerMoves.length; i++) {
            uint256 _treasureIdForMove = _playerMoves[i].treasureId;

            require(_legionQuestingInfo.treasureIds.contains(_treasureIdForMove), "Cannot play treasure that was not staked");

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
                _treasures[_treasureIndex] = Treasure(_treasureIdForMove, _legionQuestingInfo.treasureIdToAmount[_treasureIdForMove] - 1);
                _treasureIndex++;
            }
        }
    }

    // Ensures the legion is done with the current part they are on.
    // This includes checking the end time and making sure they played treasure triad.
    function _ensureDoneWithCurrentPart(
        uint256 _legionId,
        LegionQuestingInfo storage _legionQuestingInfo,
        LegionMetadata memory _legionMetadata,
        ZoneInfo storage _zoneInfo,
        uint256 _randomNumber,
        bool _checkPlayedTriad)
    private
    view
    {
        uint8 _maxConstellationRank = _maxConstellationRankForLegionAndZone(
            _legionQuestingInfo.zoneName,
            _legionMetadata);

        // Handles checking if the legion is questing or not. Will revert if not.
        // Handles checking if stasis random is ready. Will revert if not.
        (uint256 _endTime,) = _endTimeForLegion(_legionId, _legionMetadata, _maxConstellationRank, _randomNumber);
        require(block.timestamp >= _endTime, "Legion has not finished this part of the zone yet");

        // Triad played check. Only need to check the last part as _startAdvancedQuesting would have reverted
        // if they tried to skip past a triad played check.
        if(_checkPlayedTriad
            && _zoneInfo.parts[_legionQuestingInfo.advanceToPart - 1].playTreasureTriad
            && _legionQuestingInfo.triadOutcome.timeTriadWasPlayed == 0) {

            revert("Has not played treasure triad for current part");
        }
    }

    function isLegionQuesting(uint256 _legionId) public view returns(bool) {
        return legionIdToLegionQuestingInfo[_legionId].startTime > 0;
    }

    function numberOfPartsInZone(string calldata _zoneName) public view returns(uint256) {
        return zoneNameToInfo[_zoneName].parts.length;
    }

    // Returns the end time for the legion and the number of stasis hit in all the parts of the zone.
    // If the legion is waiting through stasis caused by corrupt cards in treasure triad, the second number will be the number of cards remaining.
    function endTimeForLegion(uint256 _legionId) external view returns(uint256, uint8) {
        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);

        uint8 _maxConstellationRank = _maxConstellationRankForLegionAndZone(
            legionIdToLegionQuestingInfo[_legionId].zoneName,
            _legionMetadata);

        uint256 _randomNumber = randomizer.revealRandomNumber(legionIdToLegionQuestingInfo[_legionId].requestId);

        return _endTimeForLegion(_legionId, _legionMetadata, _maxConstellationRank, _randomNumber);
    }

    function _endTimeForLegion(
        uint256 _legionId,
        LegionMetadata memory _legionMetadata,
        uint8 _maxConstellationRank,
        uint256 _randomNumber)
    private
    view
    returns(uint256, uint8)
    {
        require(isLegionQuesting(_legionId), "Legion is not questing");

        LegionQuestingInfo storage _legionQuestingInfo = legionIdToLegionQuestingInfo[_legionId];

        ZoneInfo storage _zoneInfo = zoneNameToInfo[_legionQuestingInfo.zoneName];

        uint256 _triadPlayTime = _legionQuestingInfo.triadOutcome.timeTriadWasPlayed;
        uint256 _corruptCellsRemaining = _legionQuestingInfo.triadOutcome.corruptedCellsRemainingForCurrentPart;

        // If this part requires treasure triad, and the user has already played it for this part,
        // AND the use had a corrupted card... the end time will be based on that stasis.
        if(_zoneInfo.parts[_legionQuestingInfo.advanceToPart - 1].playTreasureTriad
            && _triadPlayTime > 0
            && _corruptCellsRemaining > 0)
        {
            return (_triadPlayTime + (_corruptCellsRemaining * stasisLengthForCorruptedCard), uint8(_corruptCellsRemaining));
        }

        uint256 _totalLength = 0;

        uint8 _baseRateReduction = maxConstellationRankToReductionInStasis[_maxConstellationRank];

        uint8 _stasisHitCount = 0;

        // For example, assume currentPart is 0 and they are advancing to part 1.
        // We will go through this for loop once. The first time, i = 0, which is also
        // the index of the parts array in the ZoneInfo object.
        for(uint256 i = _legionQuestingInfo.currentPart; i < _legionQuestingInfo.advanceToPart; i++) {
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

        return (legionIdToLegionQuestingInfo[_legionId].startTime + _totalLength, _stasisHitCount);
    }

    function currentPartForLegion(uint256 _legionId) external view returns(uint8) {
        return legionIdToLegionQuestingInfo[_legionId].currentPart;
    }

    function advanceToPartForLegion(uint256 _legionId) external view returns(uint8) {
        return legionIdToLegionQuestingInfo[_legionId].advanceToPart;
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
