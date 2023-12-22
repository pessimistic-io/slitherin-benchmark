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

        uint256 _lpNeeded = 0;
        uint256 _magicNeeded = 0;
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            (uint256 _lpForSummon, uint256 _magicForSummon) = _startSummonSingle(_tokenIds[i], _crystalIds[i]);
            _lpNeeded += _lpForSummon;
            _magicNeeded += _magicForSummon;
        }

        if(_magicNeeded > 0) {
            // Send magic straight to the treasury.
            bool _magicSuccess = magic.transferFrom(msg.sender, address(treasury), _magicNeeded);
            require(_magicSuccess, "Magic failed to transfer");

            treasury.forwardCoinsToMine(_magicNeeded);
        }

        if(_lpNeeded > 0) {
            // Unlike magic, LP will be given back so we'll store on this contract.
            bool _lpSuccess = lp.transferFrom(msg.sender, address(this), _lpNeeded);
            require(_lpSuccess, "LP failed to transfer");
        }
    }

    // Returns the amount of LP that should be staked for this token.
    function _startSummonSingle(uint256 _tokenId, uint256 _crystalId) private returns(uint256, uint256) {

        require(block.timestamp >= tokenIdToCreatedTime[_tokenId] + summoningFatigueCooldown, "Summoning fatigue still active");

        LegionMetadata memory _metadata = legionMetadataStore.metadataForLegion(_tokenId);
        require(_metadata.legionGeneration != LegionGeneration.RECRUIT, "Cannot summon with recruit");

        uint32 _summoningCountCur = tokenIdToSummonCount[_tokenId];
        tokenIdToSummonCount[_tokenId]++;

        require(_summoningCountCur < generationToMaxSummons[_metadata.legionGeneration], "Reached max summons");

        uint256 _lpAmount = _lpNeeded(_metadata.legionGeneration, _summoningCountCur);

        // Set up the state before staking the legion here. If they send crap token IDs, it will revert when the transfer occurs.
        userToSummoningsInProgress[msg.sender].add(_tokenId);
        _setSummoningStartTime(_tokenId);
        uint256 _requestId = randomizer.requestRandomNumber();
        tokenIdToRequestId[_tokenId] = _requestId;
        tokenIdToLPStaked[_tokenId] = _lpAmount;

        if(_crystalId != 0) {
            require(crystalIds.contains(_crystalId), "Bad crystal ID");

            tokenIdToCrystalIdUsed[_tokenId] = _crystalId;
            consumable.adminSafeTransferFrom(msg.sender, address(treasury), _crystalId, 1);
        }

        legion.adminSafeTransferFrom(msg.sender, address(this), _tokenId);

        emit SummoningStarted(msg.sender, _tokenId, _requestId, block.timestamp + summoningDuration);

        return (_lpAmount, generationToMagicCost[_metadata.legionGeneration]);
    }

    function finishSummonTokens(uint256[] calldata _tokenIds)
    external
    nonZeroLength(_tokenIds)
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(userToSummoningsInProgress[msg.sender].contains(_tokenIds[i]), "Does not own token");
        }

        _finishSummon(_tokenIds);
    }


    function finishSummon()
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        uint256[] memory _inProgressSummons = userToSummoningsInProgress[msg.sender].values();

        _finishSummon(_inProgressSummons);
    }

    function _finishSummon(uint256[] memory _inProgressSummons) private {
        uint256 _numberFinished = 0;
        uint256 _lpToRefund = 0;

        for(uint256 i = 0; i < _inProgressSummons.length; i++) {
            uint256 _tokenId = _inProgressSummons[i];

            (uint256 _newTokenId, uint256 _lpRefund) = _finishSummonSingle(_tokenId);
            if(_newTokenId != 0) {
                _numberFinished++;
                _lpToRefund += _lpRefund;
                userToSummoningsInProgress[msg.sender].remove(_tokenId);

                emit SummoningFinished(msg.sender, _tokenId, _newTokenId, block.timestamp + summoningFatigueCooldown);
            }
        }

        if(_lpToRefund > 0) {
            lp.transfer(msg.sender, _lpToRefund);
        }

        if(_numberFinished ==0) {
            emit NoSummoningToFinish(msg.sender);
        }
    }

    function _finishSummonSingle(
        uint256 _tokenId)
    private
    returns(uint256, uint256)
    {
        if(!isTokenDoneSummoning(_tokenId)) {
            return (0, 0);
        }

        uint256 _requestId = tokenIdToRequestId[_tokenId];

        if(!randomizer.isRandomReady(_requestId)) {
            return (0, 0);
        }

        LegionMetadata memory _metadata = legionMetadataStore.metadataForLegion(_tokenId);

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        uint256 _newTokenId = legion.safeMint(msg.sender);
        LegionClass _newClass = LegionClass((_randomNumber % 5) + 1);

        uint256 _crystalId = tokenIdToCrystalIdUsed[_tokenId];

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

        uint256 _lpStaked = tokenIdToLPStaked[_tokenId];

        delete tokenIdToRequestId[_tokenId];
        delete tokenIdToLPStaked[_tokenId];
        delete tokenIdToSummonStartTime[_tokenId];
        delete tokenIdToCrystalIdUsed[_tokenId];

        // Transfer the original legion back to the user.
        legion.adminSafeTransferFrom(address(this), msg.sender, _tokenId);

        return (_newTokenId, _lpStaked);
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

}
