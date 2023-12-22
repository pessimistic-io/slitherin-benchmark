//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasureCorruptionHandlerContracts.sol";

contract TreasureCorruptionHandler is Initializable, TreasureCorruptionHandlerContracts {

    function initialize() external initializer {
        TreasureCorruptionHandlerContracts.__TreasureCorruptionHandlerContracts_init();
    }

    function removalStarted(
        address _user,
        uint256 _requestId,
        bytes calldata _requirementData,
        bytes calldata _userData)
    external
    whenNotPaused
    onlyCorruptionRemoval
    {
        RemovalRequirementData memory _requirement = abi.decode(_requirementData, (RemovalRequirementData));
        RemovalUserData memory _removalTreasureInfo = abi.decode(_userData, (RemovalUserData));

        // Validate they have the correct tiers and amount.
        require(_removalTreasureInfo.treasureIds.length == _removalTreasureInfo.treasureAmounts.length
            && _removalTreasureInfo.treasureAmounts.length > 0, "Bad treasure lengths");

        uint256 _totalAmount;

        for(uint256 i = 0; i < _removalTreasureInfo.treasureIds.length; i++) {
            TreasureMetadata memory _metadata = treasureMetadataStore.getMetadataForTreasureId(_removalTreasureInfo.treasureIds[i]);
            require(_metadata.tier == _requirement.tier && _removalTreasureInfo.treasureAmounts[i] > 0, "Bad tier or amount");

            _totalAmount += _removalTreasureInfo.treasureAmounts[i];
        }
        require(_totalAmount == _requirement.amount, "Bad treasure amount");

        // Transfer to this contract
        treasure.safeBatchTransferFrom(
            _user,
            address(this),
            _removalTreasureInfo.treasureIds,
            _removalTreasureInfo.treasureAmounts,
            "");

        // Save off the info
        requestIdToInfo[_requestId].treasureIds = _removalTreasureInfo.treasureIds;
        requestIdToInfo[_requestId].treasureAmounts = _removalTreasureInfo.treasureAmounts;

        emit TreasureStaked(
            _user,
            _requestId,
            _removalTreasureInfo.treasureIds,
            _removalTreasureInfo.treasureAmounts);
    }

    function removalEnded(
        address _user,
        uint256 _requestId,
        uint256 _randomNumber,
        bytes calldata)
    external
    whenNotPaused
    onlyCorruptionRemoval
    {
        // Spin to see what treasure breaks.
        TreasureRequestInfo storage _requestInfo = requestIdToInfo[_requestId];

        uint256[] memory _treasureIds = new uint256[](_requestInfo.treasureIds.length);
        uint256[] memory _treasureAmounts = new uint256[](_requestInfo.treasureIds.length);

        uint256[] memory _brokenTreasureIds = new uint256[](_requestInfo.treasureIds.length);
        uint256[] memory _brokenAmounts = new uint256[](_requestInfo.treasureIds.length);
        uint256 _brokenIndex = 0;

        for(uint256 i = 0; i < _requestInfo.treasureIds.length; i++) {
            TreasureMetadata memory _treasureMetadata = treasureMetadataStore.getMetadataForTreasureId(_requestInfo.treasureIds[i]);
            _treasureIds[i] = _requestInfo.treasureIds[i];
            _treasureAmounts[i] = _requestInfo.treasureAmounts[i];

            uint256 _treasureAmount = _requestInfo.treasureAmounts[i];
            for(uint256 j = 0; j < _treasureAmount; j++) {

                uint256 _breakResult = _randomNumber % 100000;
                if(_breakResult < _treasureMetadata.craftingBreakOdds) {
                    _brokenTreasureIds[_brokenIndex] = _requestInfo.treasureIds[i];

                    // Remove 1 from amount
                    _treasureAmounts[i]--;

                    _brokenAmounts[_brokenIndex]++;

                    if(_treasureMetadata.consumableIdDropWhenBreak > 0) {
                        consumable.mint(msg.sender, _treasureMetadata.consumableIdDropWhenBreak, 1);
                    }
                }

                _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));
            }
            if(_brokenAmounts[_brokenIndex] > 0) {
                _brokenIndex++;
            }
        }

        // Transfer any broken treasury to the treasury
        if(_brokenIndex > 0) {
            treasure.safeBatchTransferFrom(address(this), address(treasuryAddress), _brokenTreasureIds, _brokenAmounts, "");
        }

        // Send the rest of the treasure back.
        treasure.safeBatchTransferFrom(address(this), _user, _treasureIds, _treasureAmounts, "");

        emit TreasureUnstaked(_user, _requestId, _brokenTreasureIds, _brokenAmounts);
    }

    modifier onlyCorruptionRemoval() {
        require(msg.sender == address(corruptionRemoval), "Only corruption removal can call");

        _;
    }
}

struct RemovalRequirementData {
    uint8 tier;
    uint8 amount;
}

struct RemovalUserData {
    uint256[] treasureIds;
    uint256[] treasureAmounts;
}
