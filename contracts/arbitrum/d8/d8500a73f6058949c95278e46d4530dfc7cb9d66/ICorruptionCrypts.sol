// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICorruptionCrypts {
    function ownerOf(uint64 _legionSquadId) external view returns(address);

    function isLegionSquadActive(uint64 _legionSquadId) external view returns(bool);

    function legionIdsForLegionSquad(uint64 _legionSquadId) external view returns(uint32[] memory);

    function currentRoundId() external view returns(uint256);

    function getRoundStartTime() external view returns(uint256);

    function lastRoundEnteredTemple(uint64 _legionSquadId) external view returns(uint32);
}

