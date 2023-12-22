//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./QuestingSettings.sol";

abstract contract QuestingTimeKeeper is Initializable, QuestingSettings {

    function __QuestingTimeKeeper_init() internal initializer {
        QuestingSettings.__QuestingSettings_init();
    }

    function _startQuestTime(uint256 _tokenId) internal {
        tokenIdToQuestStartTime[_tokenId] = block.timestamp;
    }

    function _isQuestCooldownDone(uint256 _tokenId) internal view returns(bool) {
        uint256 _startTime = tokenIdToQuestStartTime[_tokenId];
        QuestDifficulty _questDifficulty = tokenIdToQuestDifficulty[_tokenId];
        uint256 _cooldown = difficultyToQuestLength[_questDifficulty];
        return block.timestamp >= _startTime + (_cooldown * tokenIdToNumberLoops[_tokenId]);
    }
}
