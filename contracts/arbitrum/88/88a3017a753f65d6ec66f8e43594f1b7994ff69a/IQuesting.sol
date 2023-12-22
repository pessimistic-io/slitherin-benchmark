// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IQuesting {
    function processQPGainAndLevelUp(uint256 _tokenId, uint8 _currentQuestLevel, uint256 _qpGained) external;
}
