//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./CraftingSettings.sol";

contract Crafting is Initializable, CraftingSettings {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        CraftingSettings.__CraftingSettings_init();
    }

    function startCraftingBatch(
        StartCraftingParams[] calldata _params)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(_params.length > 0, "No start crafting params given");

        for(uint256 i = 0; i < _params.length; i++) {
            _startCrafting(
                _params[i].legionId,
                _params[i].difficulty,
                _params[i].treasureIds,
                _params[i].treasureAmounts
            );
        }
    }

    function startCrafting(
        uint256 _tokenId,
        RecipeDifficulty _difficulty,
        uint256[] calldata _treasureIds,
        uint8[] calldata _treasureAmounts)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        _startCrafting(_tokenId, _difficulty, _treasureIds, _treasureAmounts);
    }

    function _startCrafting(
        uint256 _tokenId,
        RecipeDifficulty _difficulty,
        uint256[] calldata _treasureIds,
        uint8[] calldata _treasureAmounts)
    private
    {
        require(treasury.isBridgeWorldPowered(), "Bridge World not powered");

        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_tokenId);

        require(_legionMetadata.legionGeneration != LegionGeneration.RECRUIT, "Cannot craft with recruit");

        require(_legionMetadata.craftLevel >= difficultyToLevelUnlocked[_difficulty], "Difficult not unlocked");

        userToLegionsInProgress[msg.sender].add(_tokenId);

        tokenIdToCraftingStartTime[_tokenId] = block.timestamp;

        uint256 _requestId = randomizer.requestRandomNumber();
        tokenIdToRequestId[_tokenId] = _requestId;

        tokenIdToRecipeDifficulty[_tokenId] = _difficulty;

        _validateAndStoreTreasure(_tokenId, _difficulty, _treasureIds, _treasureAmounts);

        require(magic.transferFrom(msg.sender, address(this), craftingFee), "Magic did not transfer");

        tokenIdToMagicPaid[_tokenId] = craftingFee;

        // Transfer the legion to be staked in this contract. This will handle
        // cases when the user doesn't own the tokens
        legion.adminSafeTransferFrom(msg.sender, address(this), _tokenId);

        emit CraftingStarted(
            msg.sender,
            _tokenId,
            _requestId,
            block.timestamp + difficultyToRecipeLength[_difficulty],
            _treasureIds,
            _treasureAmounts,
            _difficulty);
    }

    function _validateAndStoreTreasure(
        uint256 _tokenId,
        RecipeDifficulty _difficulty,
        uint256[] calldata _treasureIds,
        uint8[] calldata _treasureAmounts)
    private
    {
        require(_treasureIds.length > 0
            && _treasureIds.length == _treasureAmounts.length, "Bad treasure input");

        uint8[5] memory _amountNeededPerTier = difficultyToAmountPerTier[_difficulty];

        uint8[] memory _amountGivenPerTier = new uint8[](5);

        // Just need to convert to an array of uint256 for the transfer function.
        uint256[] memory _treasureAmounts256 = new uint256[](_treasureAmounts.length);

        for(uint256 i = 0; i < _treasureIds.length; i++) {
            // Will revert if no metadata for the given ID. This can help prevent
            // them supplying garbage.
            TreasureMetadata memory _treasureMetadata = treasureMetadataStore.getMetadataForTreasureId(_treasureIds[i]);

            require(_treasureMetadata.tier >= 1 && _treasureMetadata.tier <= 5, "Bad treasure tier");

            _amountGivenPerTier[_treasureMetadata.tier - 1] += _treasureAmounts[i];

            _treasureAmounts256[i] = _treasureAmounts[i];

            tokenIdToStakedTreasure[_tokenId].push(StakedTreasure(_treasureAmounts[i], _treasureIds[i]));
        }

        for(uint256 i = 0; i < _amountGivenPerTier.length; i++) {
            require(_amountNeededPerTier[i] == _amountGivenPerTier[i], "Incorrect amount for recipe");
        }

        treasure.safeBatchTransferFrom(
            msg.sender,
            address(this),
            _treasureIds,
            _treasureAmounts256, "");
    }

    function revealTokensCraftings(uint256[] calldata _tokenIds)
    external
    contractsAreSet
    whenNotPaused
    nonZeroLength(_tokenIds)
    onlyEOA
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(userToLegionsInProgress[msg.sender].contains(_tokenIds[i]), "Not owned by user");

            _revealCrafting(_tokenIds[i]);
        }
    }

    function _revealCrafting(uint256 _tokenId) private {
        uint256 _requestId = tokenIdToRequestId[_tokenId];
        require(_requestId != 0, "Reward already claimed");

        require(randomizer.isRandomReady(_requestId), "Random not seeded");

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        RecipeDifficulty _difficulty = tokenIdToRecipeDifficulty[_tokenId];
        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_tokenId);

        uint256 _successOutcome = _randomNumber % 100000;

        uint256 _magicPaid = tokenIdToMagicPaid[_tokenId];

        bool _wasSuccessful = _successOutcome < difficultyToSuccessRate[_difficulty];
        uint256 _rewardId;
        uint8 _rewardAmount;
        uint256[] memory _brokenTreasureIds;
        uint256[] memory _brokenAmounts;
        uint256 _magicReimbursement;

        if(_wasSuccessful) {
            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

            (_rewardId, _rewardAmount) = _calculateAndDistributeReward(_difficulty, _legionMetadata.legionGeneration, _randomNumber);

            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

            (_brokenTreasureIds, _brokenAmounts) = _calculateBrokenTreasure(_tokenId, _randomNumber);

            _processCPGainAndLevelUp(
                _tokenId,
                _legionMetadata.craftLevel,
                difficultyToCPGained[_difficulty]
            );
        } else {
            // Fail
            _magicReimbursement = (_magicPaid * percentReturnedOnFailure) / 100;

            if(_magicReimbursement > 0) {
                bool _wasMagicTransferred = magic.transfer(msg.sender, _magicReimbursement);
                require(_wasMagicTransferred, "Magic failed to be reimbursed");
            }
        }

        // Send rest of magic to the treasury.
        if(_magicPaid > _magicReimbursement && _magicPaid > 0) {
            magic.transfer(address(treasury), _magicPaid - _magicReimbursement);
            treasury.forwardCoinsToMine(_magicPaid - _magicReimbursement);
        }

        delete tokenIdToRequestId[_tokenId];
        delete tokenIdToMagicPaid[_tokenId];

        emit CraftingRevealed(
            msg.sender,
            _tokenId,
            CraftingOutcome(
                _wasSuccessful,
                _magicReimbursement,
                _rewardId,
                _brokenTreasureIds,
                _brokenAmounts,
                _rewardAmount
            ));
    }

    function _calculateAndDistributeReward(
        RecipeDifficulty _difficulty,
        LegionGeneration _legionGeneration,
        uint256 _randomNumber)
    private
    returns(uint256, uint8)
    {
        CraftingReward[] memory _rewardOptions;
        if(difficultyToGenerationToRewards[_difficulty][_legionGeneration].length > 0) {
            _rewardOptions = difficultyToGenerationToRewards[_difficulty][_legionGeneration];
        } else {
            _rewardOptions = difficultyToRewards[_difficulty];
        }
        require(_rewardOptions.length > 0, "No rewards set for difficulty");

        uint256 _rewardResult = _randomNumber % 100000;

        uint256 _topRange = 0;
        for(uint256 i = 0; i < _rewardOptions.length; i++) {
            _topRange += _rewardOptions[i].odds;
            if(_rewardResult < _topRange) {
                consumable.mint(msg.sender, _rewardOptions[i].consumableId, _rewardOptions[i].amount);
                return (_rewardOptions[i].consumableId, _rewardOptions[i].amount);
            }
        }

        revert("Reward odds are incorrect");
    }

    function _calculateBrokenTreasure(
        uint256 _tokenId,
        uint256 _randomNumber)
    private
    returns(uint256[] memory, uint256[] memory) {
        StakedTreasure[] memory _stakedTreasures = tokenIdToStakedTreasure[_tokenId];

        uint256[] memory _brokenTreasureIds = new uint256[](_stakedTreasures.length);
        uint256[] memory _brokenAmounts = new uint256[](_stakedTreasures.length);
        uint256 _brokenIndex = 0;

        for(uint256 i = 0; i < _stakedTreasures.length; i++) {
            StakedTreasure memory _stakedTreasure = _stakedTreasures[i];
            TreasureMetadata memory _treasureMetadata = treasureMetadataStore.getMetadataForTreasureId(_stakedTreasure.treasureId);

            uint256 _treasureAmount = _stakedTreasure.amount;
            for(uint256 j = 0; j < _treasureAmount; j++) {

                uint256 _breakResult = _randomNumber % 100000;
                if(_breakResult < _treasureMetadata.craftingBreakOdds) {
                    _brokenTreasureIds[_brokenIndex] = _stakedTreasure.treasureId;

                    // Remove 1 from amount. If this is reduced to 0,
                    // when the user unstakes the legion, they won't get anything
                    // sent back.
                    tokenIdToStakedTreasure[_tokenId][i].amount--;

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
            treasure.safeBatchTransferFrom(address(this), address(treasury), _brokenTreasureIds, _brokenAmounts, "");
        }

        return (_brokenTreasureIds, _brokenAmounts);
    }

    function processCPGainAndLevelUp(uint256 _tokenId, uint8 _currentCraftingLevel, uint256 _craftingCPGained)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    contractsAreSet
    {
        _processCPGainAndLevelUp(_tokenId, _currentCraftingLevel, _craftingCPGained);
    }

    function _processCPGainAndLevelUp(uint256 _tokenId, uint8 _currentCraftingLevel, uint256 _craftingCPGained) private {
        // No need to do anything if they're at the max level.
        if(_currentCraftingLevel >= maxCraftingLevel) {
            return;
        }

        // Add CP relative to their current level.
        tokenIdToCP[_tokenId] += _craftingCPGained;

        // While the user is not max level
        // and they have enough to go to the next level.
        while(_currentCraftingLevel < maxCraftingLevel
            && tokenIdToCP[_tokenId] >= levelToCPNeeded[_currentCraftingLevel])
        {
            tokenIdToCP[_tokenId] -= levelToCPNeeded[_currentCraftingLevel];
            legionMetadataStore.increaseCraftLevel(_tokenId);
            _currentCraftingLevel++;
        }

        emit CPGained(_tokenId, _currentCraftingLevel, tokenIdToCP[_tokenId]);
    }

    function finishTokensCrafting(uint256[] calldata _tokenIds)
    external
    contractsAreSet
    whenNotPaused
    nonZeroLength(_tokenIds)
    onlyEOA
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(userToLegionsInProgress[msg.sender].contains(_tokenIds[i]), "Not owned by user");

            _finishCrafting(_tokenIds[i]);
        }
    }

    function _finishCrafting(uint256 _tokenId) private {
        uint256 _requestId = tokenIdToRequestId[_tokenId];
        require(_requestId == 0, "Reward not revealed");

        RecipeDifficulty _difficulty = tokenIdToRecipeDifficulty[_tokenId];

        // Check if crafting cooldown is done.
        require(block.timestamp >= tokenIdToCraftingStartTime[_tokenId] + difficultyToRecipeLength[_difficulty], "Not done crafting!");

        StakedTreasure[] memory _stakedTreasures = tokenIdToStakedTreasure[_tokenId];

        uint256[] memory _treasureIds = new uint256[](_stakedTreasures.length);
        uint256[] memory _treasureAmounts = new uint256[](_stakedTreasures.length);
        uint256 _treasureIndex;

        for(uint256 i = 0; i < _stakedTreasures.length; i++) {
            StakedTreasure memory _stakedTreasure = _stakedTreasures[i];

            if(_stakedTreasure.treasureId > 0 && _stakedTreasure.amount > 0) {
                _treasureIds[_treasureIndex] = _stakedTreasure.treasureId;
                _treasureAmounts[_treasureIndex] = _stakedTreasure.amount;
                _treasureIndex++;
            }
        }

        if(_treasureIndex > 0) {
            treasure.safeBatchTransferFrom(address(this), msg.sender, _treasureIds, _treasureAmounts, "");
        }

        userToLegionsInProgress[msg.sender].remove(_tokenId);
        delete tokenIdToStakedTreasure[_tokenId];
        delete tokenIdToRecipeDifficulty[_tokenId];
        delete tokenIdToCraftingStartTime[_tokenId];

        legion.adminSafeTransferFrom(address(this), msg.sender, _tokenId);

        emit CraftingFinished(msg.sender, _tokenId);
    }

    function getStakedLegions(
        address _user)
    external
    view
    returns(uint256[] memory)
    {
        return userToLegionsInProgress[_user].values();
    }
}
