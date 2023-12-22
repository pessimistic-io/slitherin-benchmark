// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./console.sol";

import "./ReentrancyGuard.sol";

import "./IAovLegacy.sol";

import "./ManagerModifier.sol";

contract AovLegacy is IAovLegacy, ManagerModifier {
  //=======================================
  // Mappings
  //=======================================
  mapping(address => mapping(uint256 => mapping(uint256 => bool)))
    public legacy;

  //=======================================
  // Events
  //=======================================
  event Chronicled(address addr, uint256 adventurerId, uint256 archetype);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  function chronicle(
    address _addr,
    uint256 _adventurerId,
    uint256 _currentArchetype,
    uint256 _archetype
  ) external override onlyManager {
    // Initialize legacy
    if (!legacy[_addr][_adventurerId][_currentArchetype]) {
      legacy[_addr][_adventurerId][_currentArchetype] = true;
    }

    // Set archetype to true
    legacy[_addr][_adventurerId][_archetype] = true;

    emit Chronicled(_addr, _adventurerId, _archetype);
  }
}

