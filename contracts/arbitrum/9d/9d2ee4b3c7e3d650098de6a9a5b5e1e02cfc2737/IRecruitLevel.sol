// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRecruitLevel {
    function increaseRecruitExp(uint256 _tokenId, uint32 _expIncrease) external;
    function recruitType(uint256 _tokenId) external view returns(RecruitType);
    function getRecruitLevel(uint256 _tokenId) external view returns(uint16);
}

enum RecruitType {
    NONE,
    COGNITION,
    PARABOLICS,
    LETHALITY,
    SIEGE_APPRENTICE,
    FIGHTER_APPRENTICE,
    ASSASSIN_APPRENTICE,
    RANGED_APPRENTICE,
    SPELLCASTER_APPRENTICE
}
