//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SummoningLPStakable.sol";

contract Summoning is Initializable, SummoningLPStakable {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        SummoningLPStakable.__SummoningLPStakable_init();
    }

    function startSummon(
        uint256[] calldata _tokenIds,
        uint256[] calldata _crystalIds)
    external
    nonZeroLength(_tokenIds)
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(!isSummoningPaused, "Summoning: Summoning is paused");
        require(_tokenIds.length == _crystalIds.length, "Crystal and Tokens must be equal");
        require(treasury.isBridgeWorldPowered(), "Bridge World not powered");

        uint256 _bcTotal = 0;
        uint256 _magicNeeded = 0;
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            (uint256 _bcForSummon, uint256 _magicForSummon) = _startSummonSingle(_tokenIds[i], _crystalIds[i]);
            _bcTotal += _bcForSummon;
            _magicNeeded += _magicForSummon;
        }

        if(_magicNeeded > 0) {
            bool _magicSuccess = magic.transferFrom(msg.sender, address(this), _magicNeeded);
            require(_magicSuccess, "Summoning: Magic failed to transfer");
        }

        if(_bcTotal > 0) {
            require(balancerCrystalId > 0, "Summoning: Balancer crystal id missing");

            balancerCrystal.adminSafeTransferFrom(msg.sender, address(this), balancerCrystalId, _bcTotal);
        }
    }

    // Returns the amount of BC that should be staked for this token.
    function _startSummonSingle(uint256 _tokenId, uint256 _crystalId) private returns(uint256, uint256) {

        require(block.timestamp >= tokenIdToCreatedTime[_tokenId] + summoningFatigueCooldown, "Summoning fatigue still active");

        LegionMetadata memory _metadata = legionMetadataStore.metadataForLegion(_tokenId);
        require(_metadata.legionGeneration != LegionGeneration.RECRUIT, "Cannot summon with recruit");

        uint32 _summoningCountCur = tokenIdToSummonCount[_tokenId];
        tokenIdToSummonCount[_tokenId]++;

        require(_summoningCountCur < generationToMaxSummons[_metadata.legionGeneration], "Reached max summons");

        // Transfer before calculating the success rate so that this legion counts in the calculation.
        legion.adminSafeTransferFrom(msg.sender, address(this), _tokenId);

        uint256 _bcAmount = _bcNeeded(_metadata.legionGeneration, _summoningCountCur);

        // Set up the state before staking the legion here. If they send crap token IDs, it will revert when the transfer occurs.
        userToSummoningsInProgress[msg.sender].add(_tokenId);
        _setSummoningStartTime(_tokenId);
        uint256 _requestId = randomizer.requestRandomNumber();
        tokenIdToRequestId[_tokenId] = _requestId;
        tokenIdToLPStaked[_tokenId] = _bcAmount;

        tokenIdToSuccessRate[_tokenId] = calculateSuccessRate();

        tokenIdToMagicAmount[_tokenId] = generationToMagicCost[_metadata.legionGeneration];

        if(_crystalId != 0) {
            require(crystalIds.contains(_crystalId), "Bad crystal ID");

            tokenIdToCrystalIdUsed[_tokenId] = _crystalId;
            consumable.adminSafeTransferFrom(msg.sender, address(treasury), _crystalId, 1);
        }

        emit SummoningStarted(msg.sender, _tokenId, _requestId, block.timestamp + summoningDuration);

        return (_bcAmount, generationToMagicCost[_metadata.legionGeneration]);
    }

    // Returns a value out of 100,000
    function calculateSuccessRate() public view returns(uint256) {
        uint256 _numberOfSummonings = legion.balanceOf(address(this));
        uint256 _numberOfCraftings = legion.balanceOf(address(crafting));

        // Just in case
        if(_numberOfCraftings == 0) {
            return 1;
        }

        return 10**25 / (10**20 + (((_numberOfSummonings * 10**5) / _numberOfCraftings) * ((successSensitivity * 10**5) / 100000))**2);
    }

    function finishSummonTokens(uint256[] calldata _tokenIds)
    external
    nonZeroLength(_tokenIds)
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        uint256 _numberFinished = 0;
        uint256 _bcToRefund = 0;

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];

            require(userToSummoningsInProgress[msg.sender].contains(_tokenId), "Does not own token");

            (uint256 _newTokenId, uint256 _bcRefund) = _finishSummonSingle(_tokenId);

            _numberFinished++;
            _bcToRefund += _bcRefund;
            userToSummoningsInProgress[msg.sender].remove(_tokenId);

            emit SummoningFinished(msg.sender, _tokenId, _newTokenId, block.timestamp + summoningFatigueCooldown);
        }

        if(_bcToRefund > 0) {
            balancerCrystal.adminSafeTransferFrom(address(this), msg.sender, balancerCrystalId, _bcToRefund);
        }
    }

    function _finishSummonSingle(
        uint256 _tokenId)
    private
    returns(uint256, uint256)
    {
        uint256 _requestId = tokenIdToRequestId[_tokenId];

        require(randomizer.isRandomReady(_requestId), "Summoning: Random is not ready");

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        bool _didSucceed = _didSummoningSucceed(_tokenId, _randomNumber);

        require(isTokenDoneSummoning(_tokenId, _didSucceed), "Summoning: Legion is not done summoning");

        uint256 _newTokenId;

        uint256 _crystalId = tokenIdToCrystalIdUsed[_tokenId];

        if(_didSucceed) {
            LegionMetadata memory _metadata = legionMetadataStore.metadataForLegion(_tokenId);

            _newTokenId = legion.safeMint(msg.sender);
            LegionClass _newClass = LegionClass((_randomNumber % 5) + 1);

            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));
            LegionRarity _newRarity = _determineRarity(_randomNumber, _metadata, _crystalId);

            legionMetadataStore.setInitialMetadataForLegion(msg.sender, _newTokenId, LegionGeneration.AUXILIARY, _newClass, _newRarity, 0);

            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));
            // Check for azure dust
            uint256 _azureResult = _randomNumber % 100000;

            if(_azureResult < chanceAzuriteDustDrop) {
                require(azuriteDustId > 0, "Azurite Dust ID not set");
                consumable.mint(msg.sender, azuriteDustId, 1);
            }

            tokenIdToCreatedTime[_newTokenId] = block.timestamp;

            // Send magic straight to the treasury.
            uint256 _magicAmount = tokenIdToMagicAmount[_tokenId];
            bool _magicSuccess = magic.transfer(address(treasury), _magicAmount);
            require(_magicSuccess, "Summoning: Magic failed to transfer to the treasury");

            treasury.forwardCoinsToMine(_magicAmount);
        } else {
            // They didn't actually summon.
            tokenIdToSummonCount[_tokenId]--;

            // Refund magic and crystal
            bool _magicSuccess = magic.transfer(msg.sender, tokenIdToMagicAmount[_tokenId]);
            require(_magicSuccess, "Summoning: Magic failed to transfer back to user");

            if(_crystalId > 0) {
                consumable.adminSafeTransferFrom(address(treasury), msg.sender, _crystalId, 1);
            }
        }

        uint256 _bcStaked = tokenIdToLPStaked[_tokenId];

        delete tokenIdToRequestId[_tokenId];
        delete tokenIdToLPStaked[_tokenId];
        delete tokenIdToSummonStartTime[_tokenId];
        delete tokenIdToCrystalIdUsed[_tokenId];

        // Transfer the original legion back to the user.
        legion.adminSafeTransferFrom(address(this), msg.sender, _tokenId);

        return (_newTokenId, _bcStaked);
    }

    function _determineRarity(uint256 _randomNumber, LegionMetadata memory _metadata, uint256 _crystalId) private view returns(LegionRarity) {
        uint256 _commonOdds = rarityToGenerationToOddsPerRarity[_metadata.legionRarity][_metadata.legionGeneration][LegionRarity.COMMON];
        uint256 _uncommonOdds = rarityToGenerationToOddsPerRarity[_metadata.legionRarity][_metadata.legionGeneration][LegionRarity.UNCOMMON];
        uint256 _rareOdds = rarityToGenerationToOddsPerRarity[_metadata.legionRarity][_metadata.legionGeneration][LegionRarity.RARE];

        if(_crystalId != 0) {
            uint256[3] memory _changedOdds = crystalIdToChangedOdds[_crystalId];
            _commonOdds -= _changedOdds[0];
            _uncommonOdds += _changedOdds[1];
            _rareOdds += _changedOdds[2];
        }

        require(_commonOdds + _uncommonOdds + _rareOdds == 100000, "Bad Rarity odds");

        uint256 _result = _randomNumber % 100000;

        if(_result < _commonOdds) {
            return LegionRarity.COMMON;
        } else if(_result < _commonOdds + _uncommonOdds) {
            return LegionRarity.UNCOMMON;
        } else {
            return LegionRarity.RARE;
        }
    }

    // Returns whether summoning succeded and the end time for the legion.
    function didSummoningSucceed(uint256 _tokenId) external view returns(bool, uint256) {
        uint256 _requestId = tokenIdToRequestId[_tokenId];
        require(_requestId > 0, "Summoning: Summoning not in progress for token");
        require(randomizer.isRandomReady(_requestId), "Summoning: Random is not ready");

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        bool _succeeded = _didSummoningSucceed(_tokenId, _randomNumber);

        return (_succeeded, _getTokenEndTime(_tokenId, _succeeded));
    }

    function _didSummoningSucceed(uint256 _tokenId, uint256 _randomNumber) private view returns(bool) {
        // Some random number. Doesn't really matter. Ensure this seed is unrelated to the seed used for picking class.
        _randomNumber = uint256(keccak256(abi.encode(_randomNumber, 35976445988152254298657094197983652404179925051360399363530388281034017204761)));

        uint256 _successRate = tokenIdToSuccessRate[_tokenId];

        // For backwards compatibility. The calculated success rate will never be 0 itself,
        // so this should be safe to do.
        if(_successRate == 0) {
            return true;
        }

        uint256 _successResult = _randomNumber % 100000;

        return _successResult < _successRate;
    }

    function getStakedLegions(
        address _user)
    external
    view
    returns(uint256[] memory)
    {
        return userToSummoningsInProgress[_user].values();
    }
}
