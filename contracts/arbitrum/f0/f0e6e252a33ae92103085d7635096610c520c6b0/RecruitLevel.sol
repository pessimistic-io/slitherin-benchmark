//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./RecruitLevelSettings.sol";

contract RecruitLevel is Initializable, RecruitLevelSettings {

    function initialize() external initializer {
        RecruitLevelSettings.__RecruitLevelSettings_init();
    }

    // Increase the token IDs recruit XP. Note, this should only be called by a caller who
    // has verified that _tokenId is actually a recruit.
    //
    function increaseRecruitExp(
        uint256 _tokenId,
        uint32 _expIncrease)
    external
    contractsAreSet
    whenNotPaused
    onlyAdminOrOwner
    {
        uint16 _levelCur = getRecruitLevel(_tokenId);
        uint32 _expCur = tokenIdToRecruitInfo[_tokenId].expCur;

        // No need to do anything if they're at the max level.
        if(_levelCur >= maxLevel) {
            return;
        }

        _expCur += _expIncrease;

        // While the user is not max level
        // and they have enough to go to the next level.
        while(_levelCur < maxLevel
            && _expCur >= levelCurToLevelUpInfo[_levelCur].expToNextLevel)
        {
            _expCur -= levelCurToLevelUpInfo[_levelCur].expToNextLevel;
            _levelCur++;
        }

        tokenIdToRecruitInfo[_tokenId].levelCur = _levelCur;
        tokenIdToRecruitInfo[_tokenId].expCur = _expCur;
        emit RecruitXPChanged(_tokenId, _levelCur, _expCur);
    }

    // Used to ascend to cadet and ascend to apprentice.
    function ascend(
        uint256 _tokenId,
        RecruitType _newRecruitType)
    external
    onlyEOA
    contractsAreSet
    whenNotPaused
    {
        require(legion.ownerOf(_tokenId) == msg.sender, "Not owner of Recruit");

        LegionMetadata memory _legionMetadata = legionMetadataStore.metadataForLegion(_tokenId);
        require(_legionMetadata.legionGeneration == LegionGeneration.RECRUIT, "Not a Recruit");

        RecruitType _recruitTypeCur = tokenIdToRecruitInfo[_tokenId].recruitType;

        uint16 _levelCur = getRecruitLevel(_tokenId);
        uint16 _minimumLevel;
        uint16 _numEoSToBurn;
        uint16 _numPrismShardsToBurn;

        if(_recruitTypeCur == RecruitType.NONE) {
            require(_newRecruitType == RecruitType.COGNITION
                || _newRecruitType == RecruitType.PARABOLICS
                || _newRecruitType == RecruitType.LETHALITY,
                "Bad Recruit type");

            _minimumLevel = ascensionInfo.minimumLevelCadet;
            _numEoSToBurn = ascensionInfo.numEoSCadet;
            _numPrismShardsToBurn = ascensionInfo.numPrismShardsCadet;

            require(_levelCur >= ascensionInfo.minimumLevelCadet, "Level too low to ascend");
        } else {
            bool _isValidCombination = false;
            if(_recruitTypeCur == RecruitType.COGNITION) {
                _isValidCombination = _newRecruitType == RecruitType.SPELLCASTER_APPRENTICE;
            } else if(_recruitTypeCur == RecruitType.PARABOLICS) {
                _isValidCombination = _newRecruitType == RecruitType.RANGED_APPRENTICE || _newRecruitType == RecruitType.SIEGE_APPRENTICE;
            } else if(_recruitTypeCur == RecruitType.LETHALITY) {
                _isValidCombination = _newRecruitType == RecruitType.ASSASSIN_APPRENTICE || _newRecruitType == RecruitType.FIGHTER_APPRENTICE;
            } else {
                revert("Recruit must be a cadet to become an apprentice");
            }

            // Verify the recruit type is correct.
            require(_isValidCombination, "Bad recruit type");

            _minimumLevel = ascensionInfo.minimumLevelApprentice;
            _numEoSToBurn = ascensionInfo.numEoSApprentice;
            _numPrismShardsToBurn = ascensionInfo.numPrismShardsApprentice;
        }

        require(_levelCur >= _minimumLevel, "Level too low to ascend");

        consumable.adminBurn(msg.sender, EOS_ID, _numEoSToBurn);
        consumable.adminBurn(msg.sender, PRISM_SHARD_ID, _numPrismShardsToBurn);

        tokenIdToRecruitInfo[_tokenId].recruitType = _newRecruitType;
        emit RecruitTypeChanged(_tokenId, _newRecruitType);
    }

    function getRecruitLevel(uint256 _tokenId) public view returns(uint16) {
        uint16 _levelCur = tokenIdToRecruitInfo[_tokenId].levelCur;
        // Uninitialized
        if(_levelCur == 0) {
            _levelCur = 1;
        }
        return _levelCur;
    }

    function recruitType(uint256 _tokenId) external view returns(RecruitType) {
        return tokenIdToRecruitInfo[_tokenId].recruitType;
    }
}
