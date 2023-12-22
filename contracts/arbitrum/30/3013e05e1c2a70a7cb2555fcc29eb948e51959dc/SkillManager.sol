// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISkills.sol";
import "./UserAccessible_Constants.sol";

abstract contract SkillManager {

  ISkills public skills;

  constructor (address _skills) {
    _setSkills(_skills);
  }

  function _setSkills (address _skills) internal {
    skills = ISkills(_skills);
  }

}
