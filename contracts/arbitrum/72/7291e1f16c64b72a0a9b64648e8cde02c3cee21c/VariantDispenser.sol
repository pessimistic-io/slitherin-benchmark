// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IAdventurerData.sol";
import "./IAovLegacy.sol";

import "./ManagerModifier.sol";

contract VariantDispenser is Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IAdventurerData public immutable ADVENTURER_DATA;
  IAovLegacy public immutable LEGACY;

  //=======================================
  // Events
  //=======================================
  event Dispensed(address addr, uint256 id, uint256 archetypeId);

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _manager,
    address _adventurerData,
    address _legacy
  ) ManagerModifier(_manager) {
    ADVENTURER_DATA = IAdventurerData(_adventurerData);
    LEGACY = IAovLegacy(_legacy);
  }

  //=======================================
  // External
  //=======================================
  function dispense(
    address[] calldata _addresses,
    uint256[] calldata _ids,
    uint256[] calldata _archetypes
  ) external whenNotPaused onlyAdmin {
    for (uint256 j = 0; j < _addresses.length; j++) {
      address addr = _addresses[j];
      uint256 id = _ids[j];
      uint256 archetypeId = _archetypes[j];

      // Update legacy
      LEGACY.chronicle(addr, id, _adventurerArchetype(addr, id), archetypeId);

      // Update level
      ADVENTURER_DATA.updateAov(addr, id, 1, archetypeId);

      emit Dispensed(addr, id, archetypeId);
    }
  }

  //=======================================
  // Admin
  //=======================================
  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }

  //=======================================
  // Internal
  //=======================================
  function _adventurerArchetype(address _addr, uint256 _adventurerId)
    internal
    view
    returns (uint256)
  {
    return ADVENTURER_DATA.aov(_addr, _adventurerId, 1);
  }
}

