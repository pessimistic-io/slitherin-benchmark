// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Pausable.sol";

import "./IBattleEntry.sol";

import "./ManagerModifier.sol";

contract BattleEntry is IBattleEntry, Pausable, ManagerModifier {
  //=======================================
  // Uints
  //=======================================
  uint256 public eligibility;

  //=======================================
  // Events
  //=======================================
  event EntrySet(address addr, uint256 id, uint256 battledAt);
  event OpponentSet(address addr, uint256 id, uint256 battledAt);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {
    eligibility = 7 days;
  }

  //=======================================
  // Mappings
  //=======================================
  mapping(address => mapping(uint256 => uint256)) public timers;

  //=======================================
  // External
  //=======================================
  function set(address _addr, uint256 _id) external override onlyManager {
    // Set battled at
    timers[_addr][_id] = block.timestamp;

    emit EntrySet(_addr, _id, block.timestamp);
  }

  function isEligible(
    address _oppAddr,
    uint256 _oppId
  ) external override returns (bool) {
    // Init opponent
    if (timers[_oppAddr][_oppId] == 0) {
      timers[_oppAddr][_oppId] = block.timestamp;

      emit OpponentSet(_oppAddr, _oppId, block.timestamp);
    }

    return block.timestamp - timers[_oppAddr][_oppId] < eligibility;
  }

  //=======================================
  // Admin
  //=======================================
  function updateEligibility(uint256 _value) external onlyAdmin {
    eligibility = _value;
  }
}

