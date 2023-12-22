// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISkills {
  function experienceOf(uint playerId, uint skillId) external view returns (uint);
  function validSkill (uint skillId) external view returns (bool);
  function addExperience (uint playerId, uint skillId, uint32 experience) external;
}
