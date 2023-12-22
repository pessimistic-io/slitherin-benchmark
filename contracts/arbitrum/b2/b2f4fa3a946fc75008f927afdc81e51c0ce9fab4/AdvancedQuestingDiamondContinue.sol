//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdvancedQuestingDiamondState.sol";

contract AdvancedQuestingDiamondContinue is Initializable, AdvancedQuestingDiamondState {

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
}
