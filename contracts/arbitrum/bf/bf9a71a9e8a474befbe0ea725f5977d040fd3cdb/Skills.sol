// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Types.sol";
import "./UserAccessible_Constants.sol";

import "./UserAccessible.sol";

contract Skills is
  UserAccessible
{

  Skill[] skills;

  mapping (uint => mapping (uint => PlayerSkill)) playerToSkill;

  event ExperienceAdded (uint playerId, uint skillId, uint added, uint total);

  constructor(
    address _userAccess
  )
    UserAccessible(_userAccess)
  {}

  function experienceOfBatch (uint[] calldata playerIds, uint[] calldata skillIds) public view returns (uint[] memory) {
    require(playerIds.length == skillIds.length, 'NON_EQUAL_LENGTH');
    uint[] memory exps = new uint[](playerIds.length);
    for (uint i = 0; i < playerIds.length; i++) {
      exps[i] = playerToSkill[playerIds[i]][skillIds[i]].experience;
    }
    return exps;
  }

  function experienceOf(uint playerId, uint skillId) public view returns (uint) {
    return playerToSkill[playerId][skillId].experience;
  }

  function validSkill (uint skillId) public view returns (bool) {
    return skills[skillId].active;
  }

  function numberOfSkills () public view returns (uint) { 
    return skills.length; 
  }

  function getSkill (uint skillId) public view returns (Skill memory) {
    return skills[skillId];
  }

  function addSkill (bool active) public adminOrRole(SKILL_MANAGER) {
    skills.push(Skill({
      active: active
    }));
  }

  function updateSkill (uint skillId, bool active) public adminOrRole(SKILL_MANAGER) {
    skills[skillId].active = active;
  }

  function addExperience (uint playerId, uint skillId, uint32 experience) 
    public 
    adminOrRole(MINT_EXPERIENCE) 
  {
    PlayerSkill storage player = playerToSkill[playerId][skillId];
    player.experience += experience;
    emit ExperienceAdded(playerId, skillId, experience, player.experience);
  }

}
