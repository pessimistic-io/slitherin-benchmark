//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BeaconQuestingContracts.sol";

contract BeaconQuesting is Initializable, BeaconQuestingContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        BeaconQuestingContracts.__BeaconQuestingContracts_init();
    }

    function startQuesting(StartQuestingParams[] calldata _params) external onlyEOA {

        uint64 _requestId = uint64(randomizer.requestRandomNumber());
        for(uint256 i = 0; i < _params.length; i++) {
            _startQuesting(_params[i].tokenId, false, _requestId);
        }

        questInfo.totalQuestingCharacters += uint64(_params.length);
        emit TotalQuestingCharactersUpdated(questInfo.totalQuestingCharacters);
    }

    function _startQuesting(uint128 _tokenId, bool _isRestarting, uint64 _requestId) private {
        UserInfo storage _userInfo = addressToInfo[msg.sender];
        TokenInfo storage _tokenInfo = tokenIdToInfo[_tokenId];

        if(!_isRestarting) {
            uint128 _tokenType = beacon.getTokenType(_tokenId);
            require(_tokenType == REQUIRED_CHARACTER_TYPE, "Bad character type");

            beacon.safeTransferFrom(msg.sender, address(this), _tokenId, 1, "");

            _userInfo.stakedTokens.add(_tokenId);
        }

        _tokenInfo.startTime = uint128(block.timestamp);
        _tokenInfo.requestId = _requestId;
    }

    function endQuesting(EndQuestingParams calldata _params) external onlyEOA {
        require(_params.tokenIds.length > 0, "Bad length");

        uint64 _requestId;
        if(_params.restartQuest) {
            _requestId = uint64(randomizer.requestRandomNumber());
        }

        uint64 _nullStonesMinted;

        for(uint256 i = 0; i < _params.tokenIds.length; i++) {
            bool _rewardMinted = _endQuesting(_params.tokenIds[i]);
            if(_rewardMinted) {
                _nullStonesMinted += NULL_STONE_AMOUNT;
            }

            if(_params.restartQuest) {
                _startQuesting(_params.tokenIds[i], true, _requestId);
            } else {
                addressToInfo[msg.sender].stakedTokens.remove(_params.tokenIds[i]);

                beacon.safeTransferFrom(address(this), msg.sender, _params.tokenIds[i], 1, "");
            }
        }

        if(!_params.restartQuest) {
            questInfo.totalQuestingCharacters -= uint64(_params.tokenIds.length);
            emit TotalQuestingCharactersUpdated(questInfo.totalQuestingCharacters);
        }

        emit QuestEnded(msg.sender, uint64(_params.tokenIds.length), _nullStonesMinted);
    }

    function _endQuesting(uint128 _tokenId) private returns(bool) {
        require(addressToInfo[msg.sender].stakedTokens.contains(_tokenId), "Token does not belong to user");

        TokenInfo storage _tokenInfo = tokenIdToInfo[_tokenId];
        require(_tokenInfo.startTime + questInfo.questLength < block.timestamp, "Quest is not complete");

        uint256 _randomNumber = uint256(
            keccak256(abi.encodePacked(randomizer.revealRandomNumber(_tokenInfo.requestId), _tokenId))
        );

        delete tokenIdToInfo[_tokenId];

        return masterOfInflation.tryMintFromPool(
            MintFromPoolParams(
                questInfo.poolId,
                NULL_STONE_AMOUNT,
                0,
                NULL_STONE_ID,
                _randomNumber,
                msg.sender,
                0
            )
        );
    }

    function setQuestLength(uint128 _questLength) external onlyAdminOrOwner {
        questInfo.questLength = _questLength;
        emit QuestLengthUpdated(_questLength);
    }

    function setPoolId(uint64 _poolId) external onlyAdminOrOwner {
        questInfo.poolId = _poolId;
        emit PoolIdUpdated(_poolId);
    }

    function getN(uint64) external view override returns(uint256) {
        return questInfo.totalQuestingCharacters;
    }

    function getUserQuests(address _user) external view returns(UserQuests memory) {
        uint256[] memory _allTokensForUser = addressToInfo[_user].stakedTokens.values();
        UserQuests memory _userQuests;
        _userQuests.tokenQuests = new TokenQuest[](_allTokensForUser.length);

        for(uint256 i = 0; i < _allTokensForUser.length; i++) {
            uint128 _tokenId = uint128(_allTokensForUser[i]);
            _userQuests.tokenQuests[i].tokenId = _tokenId;
            _userQuests.tokenQuests[i].startTime = tokenIdToInfo[_tokenId].startTime;
            _userQuests.tokenQuests[i].endTime = _userQuests.tokenQuests[i].startTime + questInfo.questLength;
        }

        return _userQuests;
    }
}

struct UserQuests {
    TokenQuest[] tokenQuests;
}

struct TokenQuest {
    uint128 tokenId;
    uint128 startTime;
    uint128 endTime;
}

struct StartQuestingParams {
    uint128 tokenId;
}

struct EndQuestingParams {
    uint128[] tokenIds;
    bool restartQuest;
}
