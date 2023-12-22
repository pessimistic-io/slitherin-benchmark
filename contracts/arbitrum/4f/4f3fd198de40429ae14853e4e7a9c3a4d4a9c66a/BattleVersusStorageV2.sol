// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IBattleVersusStorageV2.sol";
import "./IAdventurerData.sol";

import "./ManagerModifier.sol";

contract BattleVersusStorageV2 is IBattleVersusStorageV2, ManagerModifier {
  //=======================================
  // Uints
  //=======================================
  uint256 public immutable DATE;
  uint256 public immutable TIME_PERIOD;

  //=======================================
  // Mappings
  //=======================================
  mapping(address => mapping(uint256 => mapping(uint256 => bool)))
    public attacker;

  //=======================================
  // Events
  //=======================================
  event AttackerEpochSet(address addr, uint256 adventurerId, uint256 epoch);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {
    DATE = 4826692800;
    TIME_PERIOD = 86400;
  }

  //=======================================
  // External
  //=======================================
  function setAttackerEpoch(address _addr, uint256 _adventurerId)
    external
    override
    onlyManager
  {
    uint256 epoch = (DATE - block.timestamp) / TIME_PERIOD;

    require(
      !attacker[_addr][_adventurerId][epoch],
      "BattleVersusStorageV2: Adventurer cannot attack yet"
    );

    attacker[_addr][_adventurerId][epoch] = true;

    emit AttackerEpochSet(_addr, _adventurerId, epoch);
  }
}

