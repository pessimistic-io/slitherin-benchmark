// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IAdventurerData.sol";

import "./ManagerModifier.sol";

contract BattleVersusStorage is ManagerModifier {
  //=======================================
  // Uints
  //=======================================
  uint256 public offset;

  //=======================================
  // Mappings
  //=======================================
  mapping(address => mapping(uint256 => uint256)) public attacker;
  mapping(address => mapping(uint256 => uint256)) public opponent;
  mapping(address => mapping(uint256 => uint256)) public wins;
  mapping(address => mapping(uint256 => uint256)) public losses;

  //=======================================
  // Events
  //=======================================
  event AttackerTimerSet(
    address addr,
    uint256 adventurerId,
    uint256 _hours,
    uint256 offset,
    uint256 timerSetTo
  );
  event OpponentTimerSet(
    address addr,
    uint256 adventurerId,
    uint256 _hours,
    uint256 offset,
    uint256 timerSetTo
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, uint256 _offset) ManagerModifier(_manager) {
    offset = _offset;
  }

  //=======================================
  // External
  //=======================================
  function setAttackerCooldown(
    address _addr,
    uint256 _adventurerId,
    uint256 _hours
  ) external onlyManager {
    require(
      attacker[_addr][_adventurerId] <= block.timestamp,
      "BattleVersusStorage: Adventurer cannot attack yet"
    );

    attacker[_addr][_adventurerId] = block.timestamp + (_hours * 3600) - offset;

    emit AttackerTimerSet(
      _addr,
      _adventurerId,
      _hours,
      offset,
      attacker[_addr][_adventurerId]
    );
  }

  function setOpponentCooldown(
    address _addr,
    uint256 _adventurerId,
    uint256 _hours
  ) external onlyManager {
    require(
      opponent[_addr][_adventurerId] <= block.timestamp,
      "BattleVersusStorage: Opponent cannot be attacked yet"
    );

    opponent[_addr][_adventurerId] = block.timestamp + (_hours * 3600) - offset;

    emit OpponentTimerSet(
      _addr,
      _adventurerId,
      _hours,
      offset,
      opponent[_addr][_adventurerId]
    );
  }

  function updateWins(
    address _addr,
    uint256 _adventurerId,
    uint256 _value
  ) external onlyManager {
    wins[_addr][_adventurerId] += _value;
  }

  function updateLosses(
    address _addr,
    uint256 _adventurerId,
    uint256 _value
  ) external onlyManager {
    losses[_addr][_adventurerId] += _value;
  }

  //=======================================
  // Admin
  //=======================================
  function updateOffset(uint256 _value) external onlyAdmin {
    offset = _value;
  }
}

