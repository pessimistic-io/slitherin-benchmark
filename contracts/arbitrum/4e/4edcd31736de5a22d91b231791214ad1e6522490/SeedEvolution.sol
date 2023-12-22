//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./StringsUpgradeable.sol";

import "./SeedEvolutionSettings.sol";

contract SeedEvolution is Initializable, SeedEvolutionSettings {

    using SafeERC20Upgradeable for IMagic;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using StringsUpgradeable for uint256;

    function initialize() external initializer {
        SeedEvolutionSettings.__SeedEvolutionSettings_init();
    }

    function stakeSoLs(
        StakeSoLParameters[] calldata _solsToStake)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(_solsToStake.length > 0, "No SoL sent");

        uint256 _totalMagicNeeded = 0;
        uint256 _totalBCNeeded = 0;
        uint256 _totalSol1 = 0;
        uint256 _totalSol2 = 0;

        for(uint256 i = 0; i < _solsToStake.length; i++) {
            StakeSoLParameters memory _solToStake = _solsToStake[i];

            require(_solToStake.treasureIds.length == _solToStake.treasureAmounts.length,
                "Treasure id and amount array have bad lengths");

            if(_solToStake.solId == seedOfLife1Id) {
                _totalSol1++;
            } else if(_solToStake.solId == seedOfLife2Id) {
                _totalSol2++;
            } else {
                revert("Invalid SoL ID");
            }

            if(_solToStake.path == Path.MAGIC) {
                _totalMagicNeeded += magicCost;
            } else if(_solToStake.path == Path.MAGIC_AND_BC) {
                _totalMagicNeeded += magicCost;
                _totalBCNeeded += balancerCrystalStakeAmount;
            }

            _createLifeform(_solToStake);

            if(_solToStake.treasureIds.length > 0) {
                treasure.safeBatchTransferFrom(
                    msg.sender,
                    address(this),
                    _solToStake.treasureIds,
                    _solToStake.treasureAmounts,
                    "");
            }
        }

        if(_totalSol1 > 0) {
            seedOfLife.safeTransferFrom(msg.sender, address(this), seedOfLife1Id, _totalSol1, "");
        }
        if(_totalSol2 > 0) {
            seedOfLife.safeTransferFrom(msg.sender, address(this), seedOfLife2Id, _totalSol2, "");
        }
        if(_totalMagicNeeded > 0) {
            magic.safeTransferFrom(msg.sender, treasuryAddress, _totalMagicNeeded);
        }
        if(_totalBCNeeded > 0) {
            balancerCrystal.adminSafeTransferFrom(msg.sender, address(this), balancerCrystalId, _totalBCNeeded);
        }
    }

    function _createLifeform(StakeSoLParameters memory _solToStake) private {
        require(_solToStake.firstRealm != _solToStake.secondRealm, "First and second realm must differ");

        require(_solToStake.path != Path.NO_MAGIC || _solToStake.treasureIds.length == 0, "No magic path cannot stake treasures");

        uint256 _requestId = randomizer.requestRandomNumber();

        uint256 _lifeformId = lifeformIdCur;
        lifeformIdCur++;

        uint256 _totalTreasureBoost = 0;

        for(uint256 i = 0; i < _solToStake.treasureIds.length; i++) {
            require(_solToStake.treasureAmounts[i] > 0, "0 treasure amount");

            TreasureMetadata memory _treasureMetadata = treasureMetadataStore.getMetadataForTreasureId(_solToStake.treasureIds[i]);

            uint256 _treasureBoost = treasureTierToBoost[_treasureMetadata.tier];
            require(_treasureBoost > 0, "Boost for tier is 0");

            _totalTreasureBoost += _treasureBoost * _solToStake.treasureAmounts[i];
        }

        userToLifeformIds[msg.sender].add(_lifeformId);
        lifeformIdToInfo[_lifeformId] = LifeformInfo(
            block.timestamp,
            _requestId,
            msg.sender,
            _solToStake.path,
            _solToStake.firstRealm,
            _solToStake.secondRealm,
            _totalTreasureBoost,
            0,
            _solToStake.treasureIds,
            _solToStake.treasureAmounts
        );

        emit LifeformCreated(_lifeformId, lifeformIdToInfo[_lifeformId]);
    }

    function startClaimingImbuedSouls(
        uint256[] calldata _lifeformIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_lifeformIds)
    {
        for(uint256 i = 0; i < _lifeformIds.length; i++) {
            _startClaimingImbuedSoul(_lifeformIds[i]);
        }
    }

    function _startClaimingImbuedSoul(uint256 _lifeformId) private {
        require(userToLifeformIds[msg.sender].contains(_lifeformId), "User does not own this lifeform");

        LifeformInfo storage _info = lifeformIdToInfo[_lifeformId];

        require(block.timestamp >= _info.startTime + timeUntilDeath, "Too early to start claiming imbued soul");

        require(_info.unstakingRequestId == 0, "Already began claiming imbued soul");

        _info.unstakingRequestId = randomizer.requestRandomNumber();

        emit StartedClaimingImbuedSoul(_lifeformId, _info.unstakingRequestId);
    }

    function finishClaimingImbuedSouls(
        uint256[] calldata _lifeformIds)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    nonZeroLength(_lifeformIds)
    {
        for(uint256 i = 0; i < _lifeformIds.length; i++) {
            _finishClaimingImbuedSoul(_lifeformIds[i]);
        }
    }

    function _finishClaimingImbuedSoul(uint256 _lifeformId) private {
        require(userToLifeformIds[msg.sender].contains(_lifeformId), "User does not own this lifeform");

        userToLifeformIds[msg.sender].remove(_lifeformId);

        LifeformInfo storage _info = lifeformIdToInfo[_lifeformId];

        require(_info.unstakingRequestId != 0, "Claiming for lifeform has not started");
        require(randomizer.isRandomReady(_info.unstakingRequestId), "Random is not ready for lifeform");

        uint256 _randomNumber = randomizer.revealRandomNumber(_info.unstakingRequestId);

        _distributePotionsAndTreasures(_info, _randomNumber);

        // Send back BC if needed.
        if(_info.path == Path.MAGIC_AND_BC) {
            balancerCrystal.safeTransferFrom(address(this), msg.sender, balancerCrystalId, balancerCrystalStakeAmount, "");
        }

        LifeformClass _class = classForLifeform(_lifeformId);
        OffensiveSkill _offensiveSkill = offensiveSkillForLifeform(_lifeformId);
        SecondarySkill[] memory _secondarySkills = secondarySkillsForLifeform(_lifeformId);

        // Mint the imbued soul from generation 0
        imbuedSoul.safeMint(msg.sender,
            0,
            _class,
            _offensiveSkill,
            _secondarySkills,
            _info.path == Path.MAGIC_AND_BC,
            _lifeformId);

        emit ImbuedSoulClaimed(msg.sender, _lifeformId);
    }

    function _distributePotionsAndTreasures(LifeformInfo storage _info, uint256 _randomNumber) private returns(uint256) {
        if(_info.path == Path.NO_MAGIC) {
            return 0;
        }

        uint256 _odds = pathToBasePotionPercent[_info.path];
        _odds += _info.treasureBoost;

        uint256 _staminaPotionAmount;

        if(_odds >= 100000) {
            _staminaPotionAmount = staminaPotionRewardAmount;
        } else {
            uint256 _potionResult = _randomNumber % 100000;
            if(_potionResult < _odds) {
                _staminaPotionAmount = staminaPotionRewardAmount;
            }
        }

        if(_staminaPotionAmount > 0) {
            solItem.mint(msg.sender, staminaPotionId, _staminaPotionAmount);
        }

        if(_info.stakedTreasureIds.length > 0) {
            treasure.safeBatchTransferFrom(address(this), msg.sender, _info.stakedTreasureIds, _info.stakedTreasureAmounts, "");
        }

        return _staminaPotionAmount;
    }

    function startUnstakeTreasure(
        uint256 _lifeformId)
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        require(userToUnstakingTreasure[msg.sender].requestId == 0, "Unstaking treasure in progress for user");
        require(userToLifeformIds[msg.sender].contains(_lifeformId), "User does not own this lifeform");

        LifeformInfo storage _info = lifeformIdToInfo[_lifeformId];

        require(_info.unstakingRequestId == 0, "Can't unstake treasure while claiming imbued soul");
        require(_info.stakedTreasureIds.length > 0, "No treasure to unstake");

        uint256 _requestId = randomizer.requestRandomNumber();

        userToUnstakingTreasure[msg.sender] = UnstakingTreasure(
            _requestId,
            _info.stakedTreasureIds,
            _info.stakedTreasureAmounts);

        delete _info.stakedTreasureIds;
        delete _info.stakedTreasureAmounts;
        delete _info.treasureBoost;

        emit StartedUnstakingTreasure(_lifeformId, _requestId);
    }

    function finishUnstakeTreasure()
    external
    whenNotPaused
    contractsAreSet
    onlyEOA
    {
        UnstakingTreasure storage _unstakingTreasure = userToUnstakingTreasure[msg.sender];
        require(_unstakingTreasure.requestId != 0, "Unstaking treasure not in progress for user");
        require(randomizer.isRandomReady(_unstakingTreasure.requestId), "Random not ready for unstaking treasure");

        uint256 _randomNumber = randomizer.revealRandomNumber(_unstakingTreasure.requestId);

        uint256[] memory _unstakingTreasureIds = _unstakingTreasure.unstakingTreasureIds;
        uint256[] memory _unstakingTreasureAmounts = _unstakingTreasure.unstakingTreasureAmounts;

        uint256[] memory _brokenTreasureAmounts = new uint256[](_unstakingTreasureIds.length);

        delete userToUnstakingTreasure[msg.sender];

        for(uint256 i = 0; i < _unstakingTreasureIds.length; i++) {

            uint256 _amount = _unstakingTreasureAmounts[i];
            for(uint256 j = 0; j < _amount; j++) {
                if(i != 0 || j != 0) {
                    _randomNumber = uint256(keccak256(abi.encode(_randomNumber, 4677567)));
                }

                uint256 _breakResult = _randomNumber % 100000;

                if(_breakResult < treasureBreakOdds) {
                    _unstakingTreasureAmounts[i]--;
                    _brokenTreasureAmounts[i]++;
                }
            }
        }

        treasure.safeBatchTransferFrom(address(this), treasuryAddress, _unstakingTreasureIds, _brokenTreasureAmounts, "");
        treasure.safeBatchTransferFrom(address(this), msg.sender, _unstakingTreasureIds, _unstakingTreasureAmounts, "");

        emit FinishedUnstakingTreasure(msg.sender, _unstakingTreasureIds, _unstakingTreasureAmounts);
    }

    function metadataForLifeforms(uint256[] calldata _lifeformIds) external view returns(LifeformMetadata[] memory) {
        LifeformMetadata[] memory _metadatas = new LifeformMetadata[](_lifeformIds.length);

        for(uint256 i = 0; i < _lifeformIds.length; i++) {
            LifeformClass _class = classForLifeform(_lifeformIds[i]);
            uint8 _stage = _stageForLifeform(_lifeformIds[i]);

            _metadatas[i] = LifeformMetadata(
                _class,
                offensiveSkillForLifeform(_lifeformIds[i]),
                _stage,
                secondarySkillsForLifeform(_lifeformIds[i]),
                _tokenURIForLifeform(_lifeformIds[i], _class, _stage)
            );
        }

        return _metadatas;
    }

    function _stageForLifeform(uint256 _lifeformId) private view returns(uint8) {
        if(block.timestamp >= lifeformIdToInfo[_lifeformId].startTime + timeUntilDeath) {
            return 8;
        }
        return uint8((block.timestamp - lifeformIdToInfo[_lifeformId].startTime) * 8 / timeUntilDeath) + 1;
    }

    function _tokenURIForLifeform(uint256 _lifeformId, LifeformClass _class, uint8 _stage) private view returns(string memory) {
        return bytes(baseTokenUri).length > 0 ?
            string(abi.encodePacked(
                baseTokenUri,
                uint256(_class).toString(),
                "/",
                _lifeformId.toString(),
                "/",
                uint256(_stage).toString(),
                ".json"
            ))
            : "";
    }

    function lifeformIdsForUser(address _user) external view returns(uint256[] memory) {
        return userToLifeformIds[_user].values();
    }

    function classForLifeform(uint256 _lifeformId) public view returns(LifeformClass) {
        require(lifeformIdCur > _lifeformId && _lifeformId != 0, "Invalid lifeformId");

        uint256 _requestId = lifeformIdToInfo[_lifeformId].requestId;
        require(randomizer.isRandomReady(_requestId), "Random is not ready");

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        uint256 _classResult = _randomNumber % 100000;
        uint256 _topRange = 0;

        for(uint256 i = 0; i < availableClasses.length; i++) {
            _topRange += classToOdds[availableClasses[i]];
            if(_classResult < _topRange) {
                return availableClasses[i];
            }
        }

        revert("The class odds are broke");
    }

    function offensiveSkillForLifeform(uint256 _lifeformId) public view returns(OffensiveSkill) {
        LifeformClass _class = classForLifeform(_lifeformId);

        if(block.timestamp < lifeformIdToInfo[_lifeformId].startTime + timeUntilOffensiveSkill) {
            return OffensiveSkill.NONE;
        }

        return classToOffensiveSkill[_class];
    }

    function secondarySkillsForLifeform(uint256 _lifeformId) public view returns(SecondarySkill[] memory) {
        LifeformInfo storage _lifeformInfo = lifeformIdToInfo[_lifeformId];

        if(_lifeformInfo.path == Path.NO_MAGIC) {
            return new SecondarySkill[](0);
        }

        if(block.timestamp < _lifeformInfo.startTime + timeUntilFirstSecondarySkill) {
            return new SecondarySkill[](0);
        }

        uint256 _randomNumber = randomizer.revealRandomNumber(_lifeformInfo.requestId);

        // Unmodified random was used to pick class. Create "fresh" seed here.
        _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

        SecondarySkill _firstSkill = _pickSecondarySkillFromRealm(_randomNumber, _lifeformInfo.firstRealm);

        SecondarySkill[] memory _skills;

        if(block.timestamp < _lifeformInfo.startTime + timeUntilSecondSecondarySkill) {
            _skills = new SecondarySkill[](1);
            _skills[0] = _firstSkill;
            return _skills;
        }

        _randomNumber = uint256(keccak256(abi.encode(_randomNumber, _randomNumber)));

        SecondarySkill _secondSkill = _pickSecondarySkillFromRealm(_randomNumber, _lifeformInfo.secondRealm);

        _skills = new SecondarySkill[](2);
        _skills[0] = _firstSkill;
        _skills[1] = _secondSkill;
        return _skills;
    }

    function _pickSecondarySkillFromRealm(uint256 _randomNumber, LifeformRealm _realm) private view returns(SecondarySkill) {
        SecondarySkill[] storage _availableSkills = realmToSecondarySkills[_realm];

        uint256 _skillResult = _randomNumber % 100000;
        uint256 _topRange = 0;

        for(uint256 i = 0; i < _availableSkills.length; i++) {
            _topRange += secondarySkillToOdds[_availableSkills[i]];

            if(_skillResult < _topRange) {
                return _availableSkills[i];
            }
        }

        revert("Bad odds for secondary skills");
    }

}
