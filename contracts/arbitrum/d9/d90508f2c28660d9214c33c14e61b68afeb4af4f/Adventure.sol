//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./AdventureSettings.sol";

contract Adventure is Initializable, AdventureSettings {

     using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        AdventureSettings.__AdventureSettings_init();
    }

    // Comes from World.
    function startAdventure(
        address _owner,
        uint256 _tokenId,
        string calldata _adventureName,
        uint256[] calldata _itemInputIds)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _startAdventure(_owner, _tokenId, _adventureName, _itemInputIds);
    }

    // Comes from World.
    function finishAdventure(
        address _owner,
        uint256 _tokenId)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _finishAdventure(_owner, _tokenId);
    }

    // Comes from end user
    function restartAdventuring(
        uint256[] calldata _tokenIds,
        string calldata _adventureName,
        uint256[][] calldata _itemInputIds)
    external
    onlyEOA
    whenNotPaused
    nonZeroLength(_tokenIds)
    {
        require(_tokenIds.length == _itemInputIds.length, "Adventure: Bad array lengths");

        // Ensure token is owned by caller.
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(world.ownerForStakedToad(_tokenIds[i]) == msg.sender,
                "Adventure: User does not own toad");

            _finishAdventure(msg.sender, _tokenIds[i]);
            _startAdventure(msg.sender, _tokenIds[i], _adventureName, _itemInputIds[i]);
        }
    }

    function _startAdventure(
        address _owner,
        uint256 _tokenId,
        string calldata _adventureName,
        uint256[] calldata _itemInputIds)
    private
    {
        require(isKnownAdventure(_adventureName), "Adventure: Unknown adventure");

        AdventureInfo storage _adventureInfo = nameToAdventureInfo[_adventureName];

        require(block.timestamp >= _adventureInfo.adventureStart,
            "Adventure: Adventure has not started");
        require(_adventureInfo.adventureStop == 0 || block.timestamp < _adventureInfo.adventureStop,
            "Adventure: Adventure has ended");
        require(_adventureInfo.maxTimesPerToad == 0 || tokenIdToNameToCount[_tokenId][_adventureName] < _adventureInfo.maxTimesPerToad,
            "Adventure: Toad has reached max times for this adventure");
        require(_adventureInfo.maxTimesGlobally == 0 || _adventureInfo.currentTimesGlobally < _adventureInfo.maxTimesGlobally,
            "Adventure: Adventure has reached max times globally");
        require(_adventureInfo.isInputRequired.length == _itemInputIds.length,
            "Adventure: Incorrect number of inputs");

        // Set toad start time/length
        tokenIdToToadAdventureInfo[_tokenId].adventureName = _adventureName;
        tokenIdToToadAdventureInfo[_tokenId].startTime = block.timestamp;

        // Request random
        uint256 _requestId = randomizer.requestRandomNumber();
        tokenIdToToadAdventureInfo[_tokenId].requestId = _requestId;

        // Increment global/toad counts
        _adventureInfo.currentTimesGlobally++;
        tokenIdToNameToCount[_tokenId][_adventureName]++;

        uint256 _bugzReduction;

        // Save off inputs and transfer items
        (tokenIdToToadAdventureInfo[_tokenId].timeReduction,
            _bugzReduction,
            tokenIdToToadAdventureInfo[_tokenId].chanceOfSuccessChange) = _handleTransferringInputs(
            _itemInputIds,
            _adventureInfo,
            _adventureName,
            _owner,
            _tokenId);

        _handleTransferringBugz(
            _bugzReduction,
            _adventureInfo,
            _tokenId,
            _owner);

        emit AdventureStarted(
            _tokenId,
            _adventureName,
            _requestId,
            block.timestamp,
            _adventureEndTime(_tokenId),
            _chanceOfSuccess(_tokenId),
            _itemInputIds);
    }

    function _handleTransferringBugz(
        uint256 _bugzReduction,
        AdventureInfo storage _adventureInfo,
        uint256 _tokenId,
        address _owner)
    private
    {
        uint256 _bugzCost = _bugzReduction >= _adventureInfo.bugzCost
            ? 0
            : _adventureInfo.bugzCost - _bugzReduction;

        tokenIdToToadAdventureInfo[_tokenId].bugzSpent = _bugzCost;

        // Burn bugz
        if(_bugzCost > 0) {
            bugz.burn(_owner, _bugzCost);
        }
    }

    function _handleTransferringInputs(
        uint256[] calldata _itemInputIds,
        AdventureInfo storage _adventureInfo,
        string calldata _adventureName,
        address _owner,
        uint256 _tokenId)
    private
    returns(uint256 _timeReduction, uint256 _bugzReduction, int256 _chanceOfSuccessChange)
    {
        for(uint256 i = 0; i < _itemInputIds.length; i++) {
            uint256 _itemId = _itemInputIds[i];

            if(_itemId == 0 && !_adventureInfo.isInputRequired[i]) {
                continue;
            } else if(_itemId == 0) {
                revert("Adventure: Input is required");
            } else {
                require(nameToInputIndexToInputInfo[_adventureName][i].itemIds.contains(_itemId),
                    "Adventure: Incorrect input");

                uint256 _quantity = nameToInputIndexToInputInfo[_adventureName][i].itemIdToQuantity[_itemId];

                itemz.burn(_owner, _itemId, _quantity);

                tokenIdToToadAdventureInfo[_tokenId].inputItemIds.add(_itemId);
                tokenIdToToadAdventureInfo[_tokenId].inputIdToQuantity[_itemId] = _quantity;

                _timeReduction += nameToInputIndexToInputInfo[_adventureName][i].itemIdToTimeReduction[_itemId];
                _chanceOfSuccessChange += nameToInputIndexToInputInfo[_adventureName][i].itemIdToChanceOfSuccessChange[_itemId];
                _bugzReduction += nameToInputIndexToInputInfo[_adventureName][i].itemIdToBugzReduction[_itemId];
            }
        }
    }

    function _finishAdventure(
        address _owner,
        uint256 _tokenId)
    private
    {
        ToadAdventureInfo storage _toadAdventureInfo = tokenIdToToadAdventureInfo[_tokenId];

        require(_toadAdventureInfo.startTime > 0, "Adventure: Toad is not adventuring");

        AdventureInfo storage _adventureInfo = nameToAdventureInfo[_toadAdventureInfo.adventureName];

        require(block.timestamp >= _adventureEndTime(_tokenId),
            "Adventure: Toad is not done adventuring");

        require(randomizer.isRandomReady(_toadAdventureInfo.requestId),
            "Adventure: Random is not ready");

        // Prevents re-entrance, just in case
        delete _toadAdventureInfo.startTime;

        uint256 _randomNumber = randomizer.revealRandomNumber(_toadAdventureInfo.requestId);

        uint256 _successResult = _randomNumber % 100000;

        uint256 _rewardItemId;
        uint256 _rewardQuantity;

        bool _wasAdventureSuccess = _successResult < _chanceOfSuccess(_tokenId);

        if(_wasAdventureSuccess) {
            // Success!
            // Fresh random
            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

            (_rewardItemId, _rewardQuantity) = _handleAdventureSuccess(
                _randomNumber,
                _adventureInfo,
                _toadAdventureInfo,
                _owner);
        } else {
            // Failure!

            _handleAdventureFailure(
                _adventureInfo,
                _toadAdventureInfo,
                _owner);
        }

        // Clear out data
        uint256[] memory _oldInputItemIds = _toadAdventureInfo.inputItemIds.values();
        for(uint256 i = 0; i < _oldInputItemIds.length; i++) {
            _toadAdventureInfo.inputItemIds.remove(_oldInputItemIds[i]);
        }

        // Badgez! May have badgez for failure case, so check either way.
        _addBadgezIfNeeded(_owner);

        emit AdventureEnded(
            _tokenId,
            _wasAdventureSuccess,
            _rewardItemId,
            _rewardQuantity);
    }

    function _handleAdventureSuccess(
        uint256 _randomNumber,
        AdventureInfo storage _adventureInfo,
        ToadAdventureInfo storage _toadAdventureInfo,
        address _owner)
    private
    returns(uint256, uint256)
    {
        uint256 _rewardResult = _randomNumber % 100000;
        uint256 _topRange = 0;

        // Figure out adventure rewards
        for(uint256 i = 0; i < _adventureInfo.rewardOptions.length; i++) {

            RewardOption storage _rewardOption = _adventureInfo.rewardOptions[i];

            int256 _odds = _rewardOption.baseOdds;
            if(_toadAdventureInfo.inputItemIds.contains(_rewardOption.boostItemId)) {
                _odds += _rewardOption.boostAmount;
            }
            require(_odds >= 0, "Adventure: Bad odds!");

            _topRange += uint256(_odds);

            if(_rewardResult < _topRange) {
                if(_rewardOption.itemId > 0 && _rewardOption.rewardQuantity > 0) {
                    itemz.mint(_owner, _rewardOption.itemId, _rewardOption.rewardQuantity);
                    userToRewardIdToCount[_owner][_rewardOption.itemId] += _rewardOption.rewardQuantity;
                }

                if(_rewardOption.badgeId > 0) {
                    badgez.mintIfNeeded(_owner, _rewardOption.badgeId);
                }

                return (_rewardOption.itemId, _rewardOption.rewardQuantity);
            }
        }

        return (0, 0);
    }

    function _handleAdventureFailure(
        AdventureInfo storage _adventureInfo,
        ToadAdventureInfo storage _toadAdventureInfo,
        address _owner)
    private
    {
        if(_adventureInfo.bugzReturnedOnFailure && _toadAdventureInfo.bugzSpent > 0) {
            bugz.mint(_owner, _toadAdventureInfo.bugzSpent);
        }
    }

    function _addBadgezIfNeeded(
        address _owner)
    private
    {
        uint256 _log1Count = userToRewardIdToCount[_owner][log1Id];
        uint256 _log2Count = userToRewardIdToCount[_owner][log2Id];
        uint256 _log3Count = userToRewardIdToCount[_owner][log3Id];
        uint256 _log4Count = userToRewardIdToCount[_owner][log4Id];
        uint256 _log5Count = userToRewardIdToCount[_owner][log5Id];

        if(_log1Count > 0
            && _log2Count > 0
            && _log3Count > 0
            && _log4Count > 0
            && _log5Count > 0)
        {
            badgez.mintIfNeeded(_owner, allLogTypesBadgeId);
        }
    }

    function _chanceOfSuccess(uint256 _tokenId) private view returns(uint256) {
        ToadAdventureInfo storage _toadAdventureInfo = tokenIdToToadAdventureInfo[_tokenId];
        AdventureInfo storage _adventureInfo = nameToAdventureInfo[_toadAdventureInfo.adventureName];

        int256 _chanceSuccess = int256(_adventureInfo.chanceSuccess) + _toadAdventureInfo.chanceOfSuccessChange;
        if(_chanceSuccess <= 0) {
            return 0;
        } else if(_chanceSuccess >= 100000) {
            return 100000;
        } else {
            return uint256(_chanceSuccess);
        }
    }

    function _adventureEndTime(uint256 _tokenId) private view returns(uint256) {
        ToadAdventureInfo storage _toadAdventureInfo = tokenIdToToadAdventureInfo[_tokenId];
        AdventureInfo storage _adventureInfo = nameToAdventureInfo[_toadAdventureInfo.adventureName];

        return _toadAdventureInfo.startTime + _adventureInfo.lengthForToad - _toadAdventureInfo.timeReduction;
    }

}
