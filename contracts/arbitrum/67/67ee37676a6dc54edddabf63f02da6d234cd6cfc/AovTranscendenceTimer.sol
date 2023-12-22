// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IAovTranscendenceTimer.sol";

import "./ManagerModifier.sol";

contract AovTranscendenceTimer is IAovTranscendenceTimer, ManagerModifier {
  //=======================================
  // Mappings
  //=======================================
  mapping(address => mapping(uint256 => uint256)) public timer;

  //=======================================
  // Events
  //=======================================
  event TimerSet(
    address addr,
    uint256 adventurerId,
    uint256 _hours,
    uint256 timerSetTo
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  function set(
    address _addr,
    uint256 _adventurerId,
    uint256 _hours
  ) external override onlyManager {
    require(
      timer[_addr][_adventurerId] <= block.timestamp,
      "AovTranscendenceTimer: Can't transcend yet"
    );

    timer[_addr][_adventurerId] = block.timestamp + (_hours * 3600);

    emit TimerSet(_addr, _adventurerId, _hours, timer[_addr][_adventurerId]);
  }

  function canTranscend(address _addr, uint256 _adventurerId)
    external
    view
    override
    returns (bool)
  {
    return timer[_addr][_adventurerId] <= block.timestamp;
  }
}

