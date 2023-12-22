//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ERC1155HolderUpgradeable.sol";

import "./IRandomizer.sol";
import "./IAdvancedQuestingDiamond.sol";
import "./AdminableUpgradeable.sol";
import "./LibAdvancedQuestingDiamond.sol";

abstract contract AdvancedQuestingDiamondState is Initializable, AdminableUpgradeable, ERC721HolderUpgradeable, ERC1155HolderUpgradeable {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    event AdvancedQuestStarted(address _owner, uint256 _requestId, LibAdvancedQuestingDiamond.StartQuestParams _startQuestParams);
    event AdvancedQuestContinued(address _owner, uint256 _legionId, uint256 _requestId, uint8 _toPart);
    event TreasureTriadPlayed(address _owner, uint256 _legionId, bool _playerWon, uint8 _numberOfCardsFlipped, uint8 _numberOfCorruptedCardsRemaining);
    event AdvancedQuestEnded(address _owner, uint256 _legionId, AdvancedQuestReward[] _rewards);
    event QPForEndingPart(uint8 _endingPart, uint256 _qpGained);

    // Recruit events
    event SetCadetRecruitFragmentBoost(uint32 _cadetRecruitFragmentBoost);
    event SetSuccessSensitivityRecruitFragments(uint256 _successSensitivityRecruitFragments);
    event SetRecruitFragmentsDivider(uint256 _recruitFragmentsDivider);
    event SetRecruitPartInfo(string _zoneName, uint256 _zonePart, LibAdvancedQuestingDiamond.RecruitPartInfo _partInfo);

    // Used for event. Free to change
    struct AdvancedQuestReward {
        uint256 consumableId;
        uint256 consumableAmount;
        uint256 treasureFragmentId; // Assumed to be 1.
        uint256 treasureId; // Assumed to be 1.
    }

    uint256 constant EOS_ID = 8;
    uint256 constant PRISM_SHARD_ID = 9;

    LibAdvancedQuestingDiamond.AppStorage internal appStorage;

    function __AdvancedQuestingDiamondState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
        ERC721HolderUpgradeable.__ERC721Holder_init();
        ERC1155HolderUpgradeable.__ERC1155Holder_init();

        appStorage.stasisLengthForCorruptedCard = 1 days;

        appStorage.generationToCanHaveStasis[LegionGeneration.GENESIS] = false;
        appStorage.generationToCanHaveStasis[LegionGeneration.AUXILIARY] = true;

        appStorage.maxConstellationRankToReductionInStasis[1] = 10;
        appStorage.maxConstellationRankToReductionInStasis[2] = 15;
        appStorage.maxConstellationRankToReductionInStasis[3] = 20;
        appStorage.maxConstellationRankToReductionInStasis[4] = 23;
        appStorage.maxConstellationRankToReductionInStasis[5] = 38;
        appStorage.maxConstellationRankToReductionInStasis[6] = 51;
        appStorage.maxConstellationRankToReductionInStasis[7] = 64;

        appStorage.endingPartToQPGained[1] = 10;
        appStorage.endingPartToQPGained[2] = 20;
        appStorage.endingPartToQPGained[3] = 40;
        emit QPForEndingPart(1, 10);
        emit QPForEndingPart(2, 20);
        emit QPForEndingPart(3, 40);
    }

    function isValidZone(string memory _zoneName) public view returns(bool) {
        return appStorage.zoneNameToInfo[_zoneName].zoneStartTime > 0;
    }

    function _isUsingOldSchema(uint256 _legionId) internal view returns(bool) {
        return appStorage.legionIdToLegionQuestingInfoV1[_legionId].startTime > 0;
    }

    function _activeZoneForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(string storage) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].zoneName
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].zoneName;
    }

    function _ownerForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(address) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].owner
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].owner;
    }

    function _requestIdForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(uint256) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].requestId
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].requestId;
    }

    function _advanceToPartForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(uint8) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].advanceToPart
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].advanceToPart;
    }

    function _hasTreasuresStakedForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(bool) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].treasureIds.length() > 0
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].treasures.treasure1Id > 0;
    }

    function isLegionQuesting(uint256 _legionId) public view returns(bool) {
        return appStorage.legionIdToLegionQuestingInfoV1[_legionId].startTime > 0
            || appStorage.legionIdToLegionQuestingInfoV2[_legionId].startTime > 0;
    }

    // Ensures the legion is done with the current part they are on.
    // This includes checking the end time and making sure they played treasure triad.
    function _ensureDoneWithCurrentPart(
        uint256 _legionId,
        string memory _zoneName,
        bool _usingOldSchema,
        LegionMetadata memory _legionMetadata,
        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo,
        uint256 _randomNumber,
        bool _checkPlayedTriad)
    internal
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

    function _endTimeForLegion(
        uint256 _legionId,
        bool _usingOldSchema,
        string memory _zoneName,
        LegionMetadata memory _legionMetadata,
        uint8 _maxConstellationRank,
        uint256 _randomNumber)
    internal
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
        if(appStorage.zoneNameToInfo[_zoneName].parts[_advanceToPart - 1].playTreasureTriad
            && _triadPlayTime > 0
            && _corruptCellsRemaining > 0
            && appStorage.generationToCanHaveStasis[_legionMetadata.legionGeneration])
        {
            return (_triadPlayTime + (_corruptCellsRemaining * appStorage.stasisLengthForCorruptedCard), _corruptCellsRemaining);
        }

        uint256 _totalLength;

        (_totalLength, _stasisHitCount) = _calculateStasis(
            appStorage.zoneNameToInfo[_zoneName],
            _legionMetadata,
            _randomNumber,
            _maxConstellationRank,
            _currentPart,
            _advanceToPart
        );

        _endTime = _startTimeForLegion(_usingOldSchema, _legionId) + _totalLength;
    }

    function _currentPartForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(uint8) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].currentPart
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].currentPart;
    }

    function _triadPlayTimeForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(uint256) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.timeTriadWasPlayed
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].timeTriadWasPlayed;
    }

    function _cardsFlippedForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(uint8) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.cardsFlipped
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].cardsFlipped;
    }

    function _corruptedCellsRemainingForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(uint8) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].triadOutcome.corruptedCellsRemainingForCurrentPart
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].corruptedCellsRemainingForCurrentPart;
    }

    function _startTimeForLegion(bool _useOldSchema, uint256 _legionId) internal view returns(uint256) {
        return _useOldSchema
            ? appStorage.legionIdToLegionQuestingInfoV1[_legionId].startTime
            : appStorage.legionIdToLegionQuestingInfoV2[_legionId].startTime;
    }

    function _maxConstellationRankForLegionAndZone(
        string memory _zoneName,
        LegionMetadata memory _legionMetadata)
    internal
    view
    returns(uint8)
    {
        uint8 _rankConstellation1 = _legionMetadata.constellationRanks[uint256(appStorage.zoneNameToInfo[_zoneName].constellation1)];
        uint8 _rankConstellation2 = _legionMetadata.constellationRanks[uint256(appStorage.zoneNameToInfo[_zoneName].constellation2)];
        if(_rankConstellation1 > _rankConstellation2) {
            return _rankConstellation1;
        } else {
            return _rankConstellation2;
        }
    }

    function _calculateStasis(
        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo,
        LegionMetadata memory _legionMetadata,
        uint256 _randomNumber,
        uint8 _maxConstellationRank,
        uint8 _currentPart,
        uint8 _advanceToPart)
    private
    view
    returns(uint256 _totalLength, uint8 _stasisHitCount)
    {

        uint8 _baseRateReduction = appStorage.maxConstellationRankToReductionInStasis[_maxConstellationRank];

        // For example, assume currentPart is 0 and they are advancing to part 1.
        // We will go through this for loop once. The first time, i = 0, which is also
        // the index of the parts array in the ZoneInfo object.
        for(uint256 i = _currentPart; i < _advanceToPart; i++) {
            _totalLength += _zoneInfo.parts[i].zonePartLength;

            if(appStorage.generationToCanHaveStasis[_legionMetadata.legionGeneration]) {
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
}
