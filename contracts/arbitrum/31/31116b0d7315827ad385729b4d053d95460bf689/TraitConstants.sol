// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

library traits {
  // Base Ttraits
  // See AdventurerData.sol for details
  uint256 public constant ADVENTURER_TRAIT_XP = 1;
  uint256 public constant ADVENTURER_TRAIT_STRENGTH = 2;
  uint256 public constant ADVENTURER_TRAIT_DEXTERITY = 3;
  uint256 public constant ADVENTURER_TRAIT_CONSTITUTION = 4;
  uint256 public constant ADVENTURER_TRAIT_INTELLIGENCE = 5;
  uint256 public constant ADVENTURER_TRAIT_WISDOM = 6;
  uint256 public constant ADVENTURER_TRAIT_CHARISMA = 7;
  uint256 public constant ADVENTURER_TRAIT_HP = 8;
  uint256 public constant ADVENTURER_TRAIT_HP_USED = 9;

  // AoV Traits
  // See AdventurerData.sol for details
  uint256 public constant ADVENTURER_TRAIT_LEVEL = 0;
  uint256 public constant ADVENTURER_TRAIT_ARCHETYPE = 1;
  uint256 public constant ADVENTURER_TRAIT_CLASS = 2;
  uint256 public constant ADVENTURER_TRAIT_PROFESSION = 3;

  function traitNames() public pure returns (string[9] memory) {
    return [
      "Level",
      "XP",
      "Strength",
      "Dexterity",
      "Constitution",
      "Intelligence",
      "Wisdom",
      "Charisma",
      "HP"
    ];
  }

  function traitName(uint256 traitId) public pure returns (string memory) {
    return traitNames()[traitId];
  }

  struct TraitBonus {
    uint256 traitId;
    uint256 traitValue;
  }
}

