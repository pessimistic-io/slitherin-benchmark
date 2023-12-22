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
  // Uints
  //=======================================
  uint256 public offset;

  //=======================================
  // Events
  //=======================================
  event ProductionSet(uint256 realmId);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, uint256 _offset) ManagerModifier(_manager) {
    offset = _offset;
  }

  //=======================================
  // External
  //=======================================
  function setProduction(uint256 _realmId, uint256 _timestamp)
    external
    nonReentrant
    onlyManager
  {
    production[_realmId] = _timestamp - offset;

    emit ProductionSet(_realmId);
  }

  function getStartedAt(uint256 _realmId) external view returns (uint256) {
    return production[_realmId];
  }

  function isProductive(uint256 _realmId) external view returns (bool) {
    return production[_realmId] != 0;
  }

  //=======================================
  // Admin
  //=======================================
  function updateOffset(uint256 _offset) external onlyAdmin {
    offset = _offset;
  }
}

