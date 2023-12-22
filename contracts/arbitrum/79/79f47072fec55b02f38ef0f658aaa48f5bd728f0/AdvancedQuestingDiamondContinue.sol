//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdvancedQuestingDiamondState.sol";

contract AdvancedQuestingDiamondContinue is Initializable, AdvancedQuestingDiamondState {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function continueAdvancedQuesting(uint256[] calldata _legionIds)
    external
    whenNotPaused
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

        LegionMetadata memory _legionMetadata = appStorage.legionMetadataStore.metadataForLegion(_legionId);

        require(_legionMetadata.legionGeneration != LegionGeneration.RECRUIT, "Can't continue recruit");

        LibAdvancedQuestingDiamond.ZoneInfo storage _zoneInfo = appStorage.zoneNameToInfo[_zoneName];

        require(_ownerForLegion(_usingOldSchema, _legionId) == msg.sender, "Legion is not yours");

        uint256 _randomNumber = appStorage.randomizer.revealRandomNumber(_requestIdForLegion(_usingOldSchema, _legionId));

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
        uint256 _requestId = appStorage.randomizer.requestRandomNumber();

        if(_usingOldSchema) {
            appStorage.legionIdToLegionQuestingInfoV1[_legionId].startTime = block.timestamp;
            appStorage.legionIdToLegionQuestingInfoV1[_legionId].currentPart = _advanceToPart;
            appStorage.legionIdToLegionQuestingInfoV1[_legionId].advanceToPart++;
            delete appStorage.legionIdToLegionQuestingInfoV1[_legionId].triadOutcome;
            appStorage.legionIdToLegionQuestingInfoV1[_legionId].requestId = _requestId;
        } else {
            appStorage.legionIdToLegionQuestingInfoV2[_legionId].startTime = uint120(block.timestamp);
            appStorage.legionIdToLegionQuestingInfoV2[_legionId].currentPart = _advanceToPart;
            appStorage.legionIdToLegionQuestingInfoV2[_legionId].advanceToPart++;
            delete appStorage.legionIdToLegionQuestingInfoV2[_legionId].timeTriadWasPlayed;
            delete appStorage.legionIdToLegionQuestingInfoV2[_legionId].corruptedCellsRemainingForCurrentPart;
            delete appStorage.legionIdToLegionQuestingInfoV2[_legionId].cardsFlipped;
            appStorage.legionIdToLegionQuestingInfoV2[_legionId].requestId = uint80(_requestId);
        }

        emit AdvancedQuestContinued(msg.sender, _legionId, _requestId, _advanceToPart + 1);
    }

    function unstakeTreasures(
        uint256 _legionId,
        bool _usingOldSchema,
        bool _isRestarting,
        address _owner)
    public
    returns(uint256[] memory, uint256[] memory)
    {
        require(msg.sender == address(this), "Only another facet can call");

        uint256[] memory _treasureIds;
        uint256[] memory _treasureAmounts;

        if(_usingOldSchema) {
            _treasureIds = appStorage.legionIdToLegionQuestingInfoV1[_legionId].treasureIds.values();
            _treasureAmounts = new uint256[](_treasureIds.length);

            for(uint256 i = 0; i < _treasureIds.length; i++) {
                // No longer need to remove these from the mapping, as it is the old schema.
                // _legionQuestingInfo.treasureIds.remove(_treasureIds[i]);
                _treasureAmounts[i] = appStorage.legionIdToLegionQuestingInfoV1[_legionId].treasureIdToAmount[_treasureIds[i]];
            }
        } else {
            LibAdvancedQuestingDiamond.Treasures memory _treasures = appStorage.legionIdToLegionQuestingInfoV2[_legionId].treasures;
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

        if(!_isRestarting && _treasureIds.length > 0) {
            appStorage.treasure.safeBatchTransferFrom(
                address(this),
                _owner,
                _treasureIds,
                _treasureAmounts,
                "");
        }

        return (_treasureIds, _treasureAmounts);
    }
}
