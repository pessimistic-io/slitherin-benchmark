// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Pausable.sol";

import "./IMissionOneStorage.sol";

import "./ManagerModifier.sol";

contract MissionOneStorage is IMissionOneStorage, Pausable, ManagerModifier {
  //=======================================
  // Events
  //=======================================
  event StorageSet(
    address addr,
    uint256 id,
    uint256 secondsAdded,
    uint256 timerSetTo
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // Mappings
  //=======================================
  mapping(address => mapping(uint256 => uint256)) public timers;

  //=======================================
  // External
  //=======================================
  function set(
    address _addr,
    uint256 _id,
    uint256 _seconds
  ) external override onlyManager {
    // Check if can set
    require(
      timers[_addr][_id] == 0 || block.timestamp > timers[_addr][_id],
      "MissionOneStorage: Must be first time starting mission or past time chosen"
    );

    // Set end time
    timers[_addr][_id] = block.timestamp + _seconds;

    emit StorageSet(_addr, _id, _seconds, timers[_addr][_id]);
  }

  function isEligible(address _addr, uint256 _id)
    external
    view
    override
    returns (bool)
  {
    return block.timestamp < timers[_addr][_id];
  }
}

