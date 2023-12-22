// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";

import "./ManagerModifier.sol";

contract Production is ReentrancyGuard, ManagerModifier {
  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256) public production;

  //=======================================
  // Events
  //=======================================
  event ProductionSet(uint256 realmId);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  function setProduction(uint256 _realmId) external nonReentrant onlyManager {
    production[_realmId] = block.timestamp;

    emit ProductionSet(_realmId);
  }

  function getStartedAt(uint256 _realmId) external view returns (uint256) {
    return production[_realmId];
  }

  function isProductive(uint256 _realmId) external view returns (bool) {
    return production[_realmId] != 0;
  }
}

