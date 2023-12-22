// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";

import "./ManagerModifier.sol";

contract EntityTimer is ReentrancyGuard, ManagerModifier {
  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256) public timer;
  mapping(uint256 => uint256) public nourishmentCredits;

  //=======================================
  // Uints
  //=======================================
  uint256 public offset;

  //=======================================
  // Events
  //=======================================
  event Built(uint256 realmId, uint256 _hours, uint256 timerSetTo);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, uint256 _offset) ManagerModifier(_manager) {
    offset = _offset;
  }

  //=======================================
  // External
  //=======================================
  function build(uint256 _realmId, uint256 _hours)
    external
    nonReentrant
    onlyManager
  {
    require(timer[_realmId] <= block.timestamp, "EntityTimer: Can't build yet");

    timer[_realmId] = block.timestamp + (_hours * 3600) - offset;

    emit Built(_realmId, _hours, timer[_realmId]);
  }

  function canBuild(uint256 _realmId) external view returns (bool) {
    return timer[_realmId] <= block.timestamp;
  }

  //=======================================
  // Admin
  //=======================================
  function updateOffset(uint256 _offset) external onlyAdmin {
    offset = _offset;
  }
}

