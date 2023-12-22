//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CorruptionCryptsRewardsContracts.sol";

contract CorruptionCryptsRewards is Initializable, CorruptionCryptsRewardsContracts {

    function initialize() external initializer {
        CorruptionCryptsRewardsContracts.__CorruptionCryptsRewardsContracts_init();
    }

    function onLegionsArrivedAtHarvester(
        address _harvesterAddress,
        uint32[] calldata _legionIds)
    external
    whenNotPaused
    onlyCrypts
    {
        uint24 _totalCorruptionDiversionPoints = 0;

        for(uint256 i = 0; i < _legionIds.length; i++) {
            uint32 _legionId = _legionIds[i];

            LegionMetadata memory _metadata = legionMetadataStore.metadataForLegion(_legionId);

            // Lookup the diversion points for this legion.
            _totalCorruptionDiversionPoints += generationToRarityToCorruptionDiversion[_metadata.legionGeneration][_metadata.legionRarity];
        }

        harvesterCorruptionInfo.totalCorruptionDiversionPoints += _totalCorruptionDiversionPoints;

        bool _foundMatchingHarvester = false;
        for(uint256 i = 0; i < activeHarvesterInfos.length; i++) {
            if(activeHarvesterInfos[i].harvesterAddress == _harvesterAddress) {
                _foundMatchingHarvester = true;
                _addCorruptionPointsForHarvesterIndex(i, _totalCorruptionDiversionPoints);
            }
        }

        require(_foundMatchingHarvester, "Could not find matching, active harvester");

        _calculateAndAdjustHarvesterBoosts();
    }

    function onNewRoundBegin(address[] memory activeHarvesterAddresses)
    external
    onlyCrypts
    {
        // Clear out all accumulated point totals and set boosts back to 0.
        delete harvesterCorruptionInfo;

        // Reset boosts BEFORE setting the new active harvesters
        _calculateAndAdjustHarvesterBoosts();

        delete activeHarvesterInfos;
        for(uint256 i = 0; i < activeHarvesterAddresses.length; i++) {
            activeHarvesterInfos.push(HarvesterInfo(activeHarvesterAddresses[i], 0));
        }
    }

    function craftCorruption(
        CraftCorruptionParams[] calldata _params)
    external
    whenNotPaused
    onlyEOA
    {
        require(_params.length > 0, "Bad array length");

        for(uint256 i = 0; i < _params.length; i++) {
            _craftCorruption(_params[i]);
        }
    }

    function _craftCorruption(CraftCorruptionParams calldata _params) private {
        // Confirm that the indexes are good and the user owns this legion squad and legion squad is active
        require(corruptionCrypts.ownerOf(_params.legionSquadId) == msg.sender, "Not your squad");
        require(corruptionCrypts.isLegionSquadActive(_params.legionSquadId), "Squad is not active");
        require(_params.legionIdIndexes.length > 0, "Bad length");

        // Confirm that the user has reached the temple in this round OR has reached the temple last round and
        // hasn't move yet + its been less than X minutes since the time reset
        uint32 _currentRound = uint32(corruptionCrypts.currentRoundId());
        uint256 _roundStartTime = corruptionCrypts.getRoundStartTime();
        uint32 _lastRoundInTemple = corruptionCrypts.lastRoundEnteredTemple(_params.legionSquadId);

        require(_currentRound == _lastRoundInTemple
            || (_currentRound > 1 && _currentRound - 1 == _lastRoundInTemple && _roundStartTime + roundResetTimeAllowance >= block.timestamp),
            "Legion Squad cannot craft");

        uint32[] memory _legionIds = corruptionCrypts.legionIdsForLegionSquad(_params.legionSquadId);

        uint256 _totalPoolBalance = corruption.balanceOf(address(this));
        uint256 _totalCorruptionToTransfer;

        for(uint256 i = 0; i < _params.legionIdIndexes.length; i++) {
            uint16 _legionIdIndex = _params.legionIdIndexes[i];
            require(_legionIdIndex < _legionIds.length, "Bad legion index");
            uint32 _legionId = _legionIds[_legionIdIndex];
            // Confirm that the legion has not already crafted for this round
            require(legionIdToInfo[_legionId].lastRoundCrafted < _lastRoundInTemple, "Legion already crafted");

            legionIdToInfo[_legionId].lastRoundCrafted = _lastRoundInTemple;

            LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_legionId);
            require(_legionMetadata.legionGeneration == LegionGeneration.GENESIS
                || _legionMetadata.craftLevel >= minimumCraftLevelForAuxCorruption, "Craft level too low");

            uint32 _percentClaimed = generationToRarityToPercentOfPoolClaimed[_legionMetadata.legionGeneration][_legionMetadata.legionRarity];

            uint256 _claimedAmount = (uint256(_percentClaimed) * _totalPoolBalance) / 100_000;
            _totalCorruptionToTransfer += _claimedAmount;
            _totalPoolBalance -= _claimedAmount;

            emit LegionCraftedCorruption(msg.sender, _legionId, _lastRoundInTemple, _claimedAmount);
        }

        corruption.transfer(msg.sender, _totalCorruptionToTransfer);
        consumable.adminBurn(msg.sender, MALEVOLENT_PRISM_ID, _params.legionIdIndexes.length * malevolentPrismsPerCraft);
    }

    // Based on the current diversion points, calculates the diversion to each harvester and updates the boost for each.
    //
    function _calculateAndAdjustHarvesterBoosts() private {
        // Adjust boosts.
        for(uint8 i = 0; i < activeHarvesterInfos.length; i++) {
            uint24 _corruptionPoints = _corruptionPointsForHarvesterIndex(i);
            uint32 _boost = _calculateHarvesterBoost(_corruptionPoints, harvesterCorruptionInfo.totalCorruptionDiversionPoints);
            corruption.setCorruptionStreamBoost(activeHarvesterInfos[i].harvesterAddress, _boost);
        }
    }

    modifier onlyCrypts() {
        require(msg.sender == address(corruptionCrypts), "Only crypts can call.");

        _;
    }

    function _addCorruptionPointsForHarvesterIndex(uint256 _harvesterIndex, uint24 _totalCorruptionPointsToAdd) private {
        if(_harvesterIndex == 0) {
            harvesterCorruptionInfo.harvester1CorruptionPoints += _totalCorruptionPointsToAdd;
        } else if(_harvesterIndex == 1) {
            harvesterCorruptionInfo.harvester2CorruptionPoints += _totalCorruptionPointsToAdd;
        } else if(_harvesterIndex == 2) {
            harvesterCorruptionInfo.harvester3CorruptionPoints += _totalCorruptionPointsToAdd;
        } else if(_harvesterIndex == 3) {
            harvesterCorruptionInfo.harvester4CorruptionPoints += _totalCorruptionPointsToAdd;
        } else if(_harvesterIndex == 4) {
            harvesterCorruptionInfo.harvester5CorruptionPoints += _totalCorruptionPointsToAdd;
        } else if(_harvesterIndex == 5) {
            harvesterCorruptionInfo.harvester6CorruptionPoints += _totalCorruptionPointsToAdd;
        } else if(_harvesterIndex == 6) {
            harvesterCorruptionInfo.harvester7CorruptionPoints += _totalCorruptionPointsToAdd;
        } else if(_harvesterIndex == 7) {
            harvesterCorruptionInfo.harvester8CorruptionPoints += _totalCorruptionPointsToAdd;
        } else if(_harvesterIndex == 8) {
            harvesterCorruptionInfo.harvester9CorruptionPoints += _totalCorruptionPointsToAdd;
        } else {
            revert("More than 9 active harvester. Need to upgrade CorruptionCryptsRewards");
        }
    }

    function _corruptionPointsForHarvesterIndex(uint256 _harvesterIndex) private view returns(uint24 _corruptionPoints) {
        if(_harvesterIndex == 0) {
            _corruptionPoints = harvesterCorruptionInfo.harvester1CorruptionPoints;
        } else if(_harvesterIndex == 1) {
            _corruptionPoints = harvesterCorruptionInfo.harvester2CorruptionPoints;
        } else if(_harvesterIndex == 2) {
            _corruptionPoints = harvesterCorruptionInfo.harvester3CorruptionPoints;
        } else if(_harvesterIndex == 3) {
            _corruptionPoints = harvesterCorruptionInfo.harvester4CorruptionPoints;
        } else if(_harvesterIndex == 4) {
            _corruptionPoints = harvesterCorruptionInfo.harvester5CorruptionPoints;
        } else if(_harvesterIndex == 5) {
            _corruptionPoints = harvesterCorruptionInfo.harvester6CorruptionPoints;
        } else if(_harvesterIndex == 6) {
            _corruptionPoints = harvesterCorruptionInfo.harvester7CorruptionPoints;
        } else if(_harvesterIndex == 7) {
            _corruptionPoints = harvesterCorruptionInfo.harvester8CorruptionPoints;
        } else if(_harvesterIndex == 8) {
            _corruptionPoints = harvesterCorruptionInfo.harvester9CorruptionPoints;
        } else {
            revert("More than 9 active harvester. Need to upgrade CorruptionCryptsRewards");
        }
    }

    function _calculateHarvesterBoost(uint24 _totalForHarvester, uint24 _total) private pure returns(uint32) {
        if(_totalForHarvester == 0) {
            return 0;
        }
        return uint32((100_000 * uint256(_totalForHarvester)) / uint256(_total));
    }
}

struct CraftCorruptionParams {
    uint64 legionSquadId;
    uint8[] legionIdIndexes;
}
