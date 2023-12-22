// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./console.sol";

import "./IAdventurerTrainerStorage.sol";
import "./IAdventurerData.sol";

import "./ManagerModifier.sol";

contract AdventurerTrainerStorage is
  IAdventurerTrainerStorage,
  ManagerModifier
{
  //=======================================
  // Uints
  //=======================================
  uint256 public immutable DATE;
  uint256 public immutable TIME_PERIOD;

  //=======================================
  // Mappings
  //=======================================
  mapping(address => mapping(uint256 => mapping(uint256 => bool)))
    public trainee;

  //=======================================
  // Events
  //=======================================
  event EpochSet(address addr, uint256 adventurerId, uint256 epoch);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {
    DATE = 4826692800;
    TIME_PERIOD = 604800;
  }

  //=======================================
  // External
  //=======================================
  function setEpoch(
    address _addr,
    uint256 _adventurerId
  ) external override onlyManager {
    uint256 epoch = (DATE - block.timestamp) / TIME_PERIOD;

    require(
      !trainee[_addr][_adventurerId][epoch],
      "AdventurerTrainerStorage: Adventurer cannot train yet"
    );

    trainee[_addr][_adventurerId][epoch] = true;

    emit EpochSet(_addr, _adventurerId, epoch);
  }
}

