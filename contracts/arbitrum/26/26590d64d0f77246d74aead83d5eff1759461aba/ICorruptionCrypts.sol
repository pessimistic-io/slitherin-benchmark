// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ICorruptionCryptsInternal.sol";

interface ICorruptionCrypts {
    function ownerOf(uint64 _legionSquadId) external view returns(address);

    function isLegionSquadActive(uint64 _legionSquadId) external view returns(bool);

    function legionIdsForLegionSquad(uint64 _legionSquadId) external view returns(uint32[] memory);

    function currentRoundId() external view returns(uint256);

    function getRoundStartTime() external view returns(uint256);

    function lastRoundEnteredTemple(uint64 _legionSquadId) external view returns(uint32);

    function gatherLegionSquadData(uint64 _legionSquadId) external view returns(CharacterInfo[] memory);

    function collectionToCryptsCharacterHandler(address) external view returns (address);
}

