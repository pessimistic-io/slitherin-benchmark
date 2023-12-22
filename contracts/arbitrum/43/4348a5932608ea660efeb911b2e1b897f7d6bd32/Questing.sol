//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./QuestingTimeKeeper.sol";

contract Questing is Initializable, QuestingTimeKeeper {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        QuestingTimeKeeper.__QuestingTimeKeeper_init();
    }

    function startQuests(
        uint256[] calldata _tokenIds,
        QuestDifficulty[] calldata _difficulties,
        uint256[] calldata _questLoops)
    external
    nonZeroLength(_tokenIds)
    contractsAreSet
    whenNotPaused
    onlyEOA
    {
        require(_tokenIds.length == _difficulties.length
            && _questLoops.length == _difficulties.length, "Bad number of difficulties");

        require(treasury.isBridgeWorldPowered(), "Bridge World not powered.");

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_tokenIds[i]);

            if(_legionMetadata.legionGeneration == LegionGeneration.RECRUIT) {
                _startQuestRecruit(_tokenIds[i], _difficulties[i], _questLoops[i], true);
            } else {
                _startQuest(_tokenIds[i], _difficulties[i], _questLoops[i], _legionMetadata, true);
            }
        }
    }

    function _startQuestRecruit(
        uint256 _tokenId,
        QuestDifficulty _difficulty,
        uint256 _numberLoops,
        bool _transferLegionToContract)
    private
    {
        require(_numberLoops == 1, "Max 1 loop for recruit legion");
        require(_difficulty == QuestDifficulty.EASY, "Easy only for recruit");

        _startQuestTime(_tokenId);

        uint256 _requestId = randomizer.requestRandomNumber();
        tokenIdToRequestId[_tokenId] = _requestId;

        tokenIdToQuestDifficulty[_tokenId] = _difficulty;
        tokenIdToNumberLoops[_tokenId] = _numberLoops;

        if(_transferLegionToContract) {
            userToQuestsInProgress[msg.sender].add(_tokenId);

            // Transfer the legion to be staked in this contract. This will handle
            // cases when the user doesn't own the tokens
            legion.adminSafeTransferFrom(msg.sender, address(this), _tokenId);
        }

        emit QuestStarted(msg.sender, _tokenId, _requestId, block.timestamp + (difficultyToQuestLength[_difficulty] * _numberLoops), _difficulty);
    }

    function _startQuest(
        uint256 _tokenId,
        QuestDifficulty _difficulty,
        uint256 _numberLoops,
        LegionMetadata memory _legionMetadata,
        bool _transferLegionToContract)
    private
    {
        uint256 _lpStaked = 0;

        // 1 loop does not require any staked LP
        if(_numberLoops != 1) {
            require(availableAutoQuestLoops.contains(_numberLoops), "Invalid number of loops");

            _lpStaked = difficultyToLPNeeded[_difficulty] * _numberLoops;
            if(_lpStaked > 0) {
                bool _lpSuccess = lp.transferFrom(msg.sender, address(this), _lpStaked);
                require(_lpSuccess, "LP transfer failed");
            }
        }

        uint8 _levelNeededForDifficulty = difficultyToLevelUnlocked[_difficulty];
        require(_legionMetadata.questLevel >= _levelNeededForDifficulty, "Difficulty not unlocked.");

        _startQuestTime(_tokenId);

        uint256 _requestId = randomizer.requestRandomNumber();
        tokenIdToRequestId[_tokenId] = _requestId;

        tokenIdToQuestDifficulty[_tokenId] = _difficulty;
        tokenIdToLPStaked[_tokenId] = _lpStaked;
        tokenIdToNumberLoops[_tokenId] = _numberLoops;

        if(_transferLegionToContract) {
            userToQuestsInProgress[msg.sender].add(_tokenId);

            // Transfer the legion to be staked in this contract. This will handle
            // cases when the user doesn't own the tokens
            legion.adminSafeTransferFrom(msg.sender, address(this), _tokenId);
        }

        emit QuestStarted(msg.sender, _tokenId, _requestId, block.timestamp + difficultyToQuestLength[_difficulty], _difficulty);
    }

    function revealTokensQuests(uint256[] calldata _tokenIds)
    external
    contractsAreSet
    whenNotPaused
    nonZeroLength(_tokenIds)
    onlyEOA
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(userToQuestsInProgress[msg.sender].contains(_tokenIds[i]), "Not owned by user");

            _revealQuest(_tokenIds[i]);
        }
    }

    function _revealQuest(uint256 _tokenId) private {
        uint256 _requestId = tokenIdToRequestId[_tokenId];

        require(_requestId != 0, "Already revealed quests");
        require(randomizer.isRandomReady(_requestId), "Random is not ready!");

        QuestDifficulty _difficulty = tokenIdToQuestDifficulty[_tokenId];
        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);
        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_tokenId);

        for(uint256 i = 0; i < tokenIdToNumberLoops[_tokenId]; i++) {
            // Ensure each loop has a different random number.
            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, i)));

            if(_legionMetadata.legionGeneration == LegionGeneration.RECRUIT) {
                _calculateAndDistributeRewardRecruit(_tokenId, _randomNumber);
            } else {
                _calculateAndDistributeReward(_tokenId, _difficulty, _randomNumber);
                 // Process QP gain/level up.
                _processQPGainAndLevelUp(_tokenId, _legionMetadata.questLevel);
            }
        }

        delete tokenIdToRequestId[_tokenId];
    }

    function _calculateAndDistributeRewardRecruit(
        uint256 _tokenId,
        uint256 _randomNumber)
    private {
        require(starlightId != 0
            && shardId != 0
            && universalLockId != 0, "Consumable ID not set");

        // Recruits are guaranteed starlight.
        uint8 _starlightAmount = recruitNumberOfStarlight;
        if(_starlightAmount > 0) {
            consumable.mint(msg.sender, starlightId, _starlightAmount);
        }

        uint8 _shardAmount = 0;

        if(recruitNumberOfCrystalShards > 0) {
            uint256 _shardResult = _randomNumber % 100000;

            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

            if(_shardResult < recruitCrystalShardsOdds) {
                _shardAmount = recruitNumberOfCrystalShards;
                consumable.mint(msg.sender, shardId, _shardAmount);
            }
        }

        uint256 _universalLockResult = _randomNumber % 100000;
        uint8 _universalLockAmount = 0;
        if(_universalLockResult < recruitUniversalLockOdds) {
            consumable.mint(msg.sender, universalLockId, 1);
            _universalLockAmount = 1;
        }

        emit QuestRevealed(
            msg.sender,
            _tokenId,
            QuestReward(
                _starlightAmount,
                _shardAmount,
                _universalLockAmount,
                0
            )
        );
    }

    function _calculateAndDistributeReward(
        uint256 _tokenId,
        QuestDifficulty _difficulty,
        uint256 _randomNumber)
    private {
        require(starlightId != 0
            && shardId != 0
            && universalLockId != 0, "Consumable ID not set");

        // Every user is guaranteed 2 rewards per quest.
        uint8 _starlightAmount = difficultyToStarlightAmount[_difficulty];
        uint8 _shardAmount = difficultyToShardAmount[_difficulty];

        if(_starlightAmount > 0) {
            consumable.mint(msg.sender, starlightId, _starlightAmount);
        }
        if(_shardAmount > 0) {
            consumable.mint(msg.sender, shardId, _shardAmount);
        }

        uint256 _rewardedTreasureId = 0;

        uint256 _treasureResult = _randomNumber % 100000;
        if(_treasureResult < treasureDropOdds) {
            _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

            uint256 _treasureTierResult = _randomNumber % 100000;

            uint256[5] memory _tierOdds = difficultyToTierOdds[_difficulty];
            uint256 _topRange = 0;
            for(uint256 i = 0; i < _tierOdds.length; i++) {
                _topRange += _tierOdds[i];
                if(_treasureTierResult < _topRange) {
                    _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

                    // Tiers are 1 index based.
                    _rewardedTreasureId = treasureMetadataStore.getRandomTreasureForTier(uint8(i + 1), _randomNumber);

                    treasure.mint(msg.sender, _rewardedTreasureId, 1);
                    break;
                }
            }
        }

        _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

        uint256 _universalLockResult = _randomNumber % 100000;
        uint8 _universalLockAmount = 0;
        if(_universalLockResult < universalLockDropOdds) {
            consumable.mint(msg.sender, universalLockId, 1);
            _universalLockAmount = 1;
        }

        emit QuestRevealed(
            msg.sender,
            _tokenId,
            QuestReward(
                _starlightAmount,
                _shardAmount,
                _universalLockAmount,
                _rewardedTreasureId
            )
        );
    }

    function _processQPGainAndLevelUp(uint256 _tokenId, uint8 _currentQuestLevel) private {
        // No need to do anything if they're at the max level.
        if(_currentQuestLevel >= maxQuestLevel) {
            return;
        }

        // Add QP relative to their current level.
        tokenIdToQP[_tokenId] += levelToQPGainedPerQuest[_currentQuestLevel];

        // While the user is not max level
        // and they have enough to go to the next level.
        while(_currentQuestLevel < maxQuestLevel
            && tokenIdToQP[_tokenId] >= levelToQPNeeded[_currentQuestLevel])
        {
            tokenIdToQP[_tokenId] -= levelToQPNeeded[_currentQuestLevel];
            legionMetadataStore.increaseQuestLevel(_tokenId);
            _currentQuestLevel++;
        }
    }

    function finishTokenQuests(uint256[] calldata _tokenIds)
    external
    contractsAreSet
    whenNotPaused
    nonZeroLength(_tokenIds)
    onlyEOA
    {
        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(userToQuestsInProgress[msg.sender].contains(_tokenIds[i]), "Not owned by user");

            _finishQuest(_tokenIds[i], true);
        }
    }

    function restartTokenQuests(
        uint256[] calldata _tokenIds,
        QuestDifficulty[] calldata _difficulties,
        uint256[] calldata _questLoops)
    external
    contractsAreSet
    whenNotPaused
    nonZeroLength(_tokenIds)
    onlyEOA
    {
        require(_tokenIds.length == _difficulties.length
            && _questLoops.length == _difficulties.length, "Bad number of difficulties");

        require(treasury.isBridgeWorldPowered(), "Bridge World not powered.");

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            require(userToQuestsInProgress[msg.sender].contains(_tokenIds[i]), "Not owned by user");

            _finishQuest(_tokenIds[i], false);

            LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_tokenIds[i]);

            if(_legionMetadata.legionGeneration == LegionGeneration.RECRUIT) {
                _startQuestRecruit(_tokenIds[i], _difficulties[i], _questLoops[i], false);
            } else {
                _startQuest(_tokenIds[i], _difficulties[i], _questLoops[i], _legionMetadata, false);
            }
        }
    }

    function _finishQuest(uint256 _tokenId, bool _sendLegionBackAndClearData) private {
        uint256 _requestId = tokenIdToRequestId[_tokenId];
        require(_requestId == 0, "Reward not revealed yet");

        require(_isQuestCooldownDone(_tokenId), "Quest cooldown has not completed");

        uint256 _lpStakedAmount = tokenIdToLPStaked[_tokenId];

        // Save on gas by not writing unnecessarily to the chain. These will be overwritten when questing is started again
        if(_sendLegionBackAndClearData) {
            delete tokenIdToQuestDifficulty[_tokenId];
            delete tokenIdToQuestStartTime[_tokenId];
            delete tokenIdToLPStaked[_tokenId];
            delete tokenIdToNumberLoops[_tokenId];

            userToQuestsInProgress[msg.sender].remove(_tokenId);
            legion.adminSafeTransferFrom(address(this), msg.sender, _tokenId);
        }

        if(_lpStakedAmount > 0) {
            bool _lpSucceed = lp.transfer(msg.sender, _lpStakedAmount);
            require(_lpSucceed, "LP transfer failed");
        }

        emit QuestFinished(msg.sender, _tokenId);
    }

    function isQuestReadyToReveal(uint256 _tokenId) external view returns(bool) {
        uint256 _requestId = tokenIdToRequestId[_tokenId];
        require(_requestId > 0, "Not active or already revealed");

        return randomizer.isRandomReady(_requestId);
    }
}
