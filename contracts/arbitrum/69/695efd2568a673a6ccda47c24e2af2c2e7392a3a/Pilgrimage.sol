//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./CountersUpgradeable.sol";
import "./Initializable.sol";

import "./PilgrimageTimeKeeper.sol";

contract Pilgrimage is Initializable, PilgrimageTimeKeeper {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        PilgrimageTimeKeeper.__PilgrimageTimeKeeper_init();
    }

    function embarkOnPilgrimages(
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        LegionGeneration _generation)
    external
    nonZeroLength(_ids)
    lengthsAreEqual(_ids, _amounts)
    contractsAreSet
    onlyEOA
    whenNotPaused
    {
        uint256 _totalPilgrimages = 0;
        for(uint256 i = 0; i < _amounts.length; i++) {
            _totalPilgrimages += _amounts[i];
        }

        uint256[] memory _pilgrimageIds = new uint256[](_totalPilgrimages);
        uint256 _pilgrimageIdIndex = 0;

        for(uint256 i = 0; i < _ids.length; i++) {
            require(legion1155Ids.contains(_ids[i]), "No rarity found for legion ID");
            require(_amounts[i] > 0, "Bad legion amount.");

            for(uint256 j = 0; j < _amounts[i]; j++) {
                // Sends a single legion on a pilgrimage
                uint256 _pilgrimageId = _embarkOnPilgrimage(_ids[i], _generation);
                _pilgrimageIds[_pilgrimageIdIndex] = _pilgrimageId;
                _pilgrimageIdIndex++;
            }
        }

        address _legionContractAddress;

        // If not approved, this will revert. When possible state changes should be done before calling an external contract.
        if(_generation == LegionGeneration.GENESIS) {
            _legionContractAddress = address(legionGenesis1155);
            legionGenesis1155.safeBatchTransferFrom(msg.sender, address(this), _ids, _amounts, "");
        } else {
            _legionContractAddress = address(legion1155);
            legion1155.safeBatchTransferFrom(msg.sender, address(this), _ids, _amounts, "");
        }

        emit PilgrimagesStarted(msg.sender, _legionContractAddress, block.timestamp + pilgrimageLength, _ids, _amounts, _pilgrimageIds);
    }

    function _embarkOnPilgrimage(uint256 _id, LegionGeneration _generation) private returns(uint256) {
        uint256 _pilgrimageID = pilgrimageID;
        pilgrimageID++;

        pilgrimageIdToRarity[_pilgrimageID] = legionIdToRarity[_id];
        pilgrimageIdToClass[_pilgrimageID] = legionIdToClass[_id];
        pilgrimageIdToGeneration[_pilgrimageID] = _generation;
        pilgrimageIdToChanceConstellationUnlocked[_pilgrimageID] = legionIdToChanceConstellationUnlocked[_id];
        pilgrimageIdToNumberConstellationUnlocked[_pilgrimageID] = legionIdToNumberConstellationUnlocked[_id];
        pilgrimageIdToOldId[_pilgrimageID] = _id;

        _setPilgrimageStartTime(_pilgrimageID);

        uint256 _randomRequestID = randomizer.requestRandomNumber();
        pilgrimageIdToRequestId[_pilgrimageID] = _randomRequestID;

        // Add this pilgrimage to the user.
        userToPilgrimagesInProgress[msg.sender].add(_pilgrimageID);

        return _pilgrimageID;
    }

    function returnTokensFromPilgrimages(
        uint256[] calldata _pilgrimageIds)
    external
    onlyEOA
    nonZeroLength(_pilgrimageIds)
    contractsAreSet
    whenNotPaused
    {
        for(uint256 i = 0; i < _pilgrimageIds.length; i++) {
            require(userToPilgrimagesInProgress[msg.sender].contains(_pilgrimageIds[i]), "Pilg does not belong to user");
        }

        _returnFromPilgrimages(_pilgrimageIds);
    }

    function returnFromPilgrimages()
    external
    onlyEOA
    contractsAreSet
    whenNotPaused {

        uint256[] memory _inProgressPilgrimages = userToPilgrimagesInProgress[msg.sender].values();

        _returnFromPilgrimages(_inProgressPilgrimages);
    }

    function _returnFromPilgrimages(uint256[] memory _inProgressPilgrimages) private {
        uint256[] memory _minted721s = new uint256[](_inProgressPilgrimages.length);
        uint256 _minted721sIndex = 0;

        uint256[] memory _finishedPilgrimages = new uint256[](_inProgressPilgrimages.length);
        uint256 _finishedPilgrimagesIndex = 0;

        for(uint256 i = 0; i < _inProgressPilgrimages.length; i++) {
            uint256 _pilgrimageId = _inProgressPilgrimages[i];

            uint256 _tokenId721 = _returnFromPilgrimage(_pilgrimageId);
            if(_tokenId721 != 0) {
                _minted721s[_minted721sIndex] = _tokenId721;
                _minted721sIndex++;
                _finishedPilgrimages[_finishedPilgrimagesIndex] = _pilgrimageId;
                _finishedPilgrimagesIndex++;
                userToPilgrimagesInProgress[msg.sender].remove(_pilgrimageId);
            }
        }

        if(_minted721sIndex > 0) {
            emit PilgrimagesFinished(msg.sender, _minted721s, _finishedPilgrimages);
        } else {
            emit NoPilgrimagesToFinish(msg.sender);
        }
    }

    // Returns the token id of the newly minted 721 if the pilgrimage is ready.
    function _returnFromPilgrimage(uint256 _pilgrimageID) private returns(uint256) {
        if(!isPilgrimageReady(_pilgrimageID)) {
            return 0;
        }

        LegionRarity _rarity = pilgrimageIdToRarity[_pilgrimageID];
        LegionClass _class = pilgrimageIdToClass[_pilgrimageID];
        uint256 _oldId = pilgrimageIdToOldId[_pilgrimageID];

        uint256 _requestId = pilgrimageIdToRequestId[_pilgrimageID];

        if(!randomizer.isRandomReady(_requestId)) {
            return 0;
        }

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        // Commmon legions need to be assigned a new class.
        if(_rarity == LegionRarity.COMMON) {
            // There are 6 enum values, but the first is None. We want the result to be between 1 and 5.
            _class = LegionClass((_randomNumber % 5) + 1);
        }

        uint256 _tokenId = legion.safeMint(msg.sender);

        legionMetadataStore.setInitialMetadataForLegion(msg.sender, _tokenId, pilgrimageIdToGeneration[_pilgrimageID], _class, _rarity, _oldId);

        uint256 _chance = pilgrimageIdToChanceConstellationUnlocked[_pilgrimageID];
        uint8 _numberToUnlock = 0;

        if(_chance == 100000) {
            _numberToUnlock = pilgrimageIdToNumberConstellationUnlocked[_pilgrimageID];
        } else {
            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

            if(_randomNumber % 100000 < _chance) {
                _numberToUnlock = pilgrimageIdToNumberConstellationUnlocked[_pilgrimageID];
            }
        }

        if(_numberToUnlock > 0) {
            starlightTemple.maxRankOfConstellations(_tokenId, _numberToUnlock);
        }

        return _tokenId;
    }
}
