// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ManagerModifier.sol";
import "./ILootBox.sol";
import "./ILootBoxDispenser.sol";

contract LootBoxDispenser is
  ILootBoxDispenser,
  ReentrancyGuard,
  Pausable,
  ManagerModifier
{
  //=======================================
  // Immutable
  //=======================================
  ILootBox public immutable lootBox;

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, address _lootBox) ManagerModifier(_manager) {
    lootBox = ILootBox(_lootBox);
  }

  //=======================================
  // External
  //=======================================
  function dispense(
    address _address,
    uint256 _id,
    uint256 _amount
  ) external onlyManager nonReentrant whenNotPaused {
    lootBox.mintFor(_address, _id, _amount);
    emit LootBoxesDispensed(_address, _id, _amount);
  }

  function dispenseBatch(
    address _address,
    uint256[] calldata _ids,
    uint256[] calldata _amounts
  ) external onlyManager nonReentrant whenNotPaused {
    for (uint256 i = 0; i < _ids.length; i++) {
      lootBox.mintFor(_address, _ids[i], _amounts[i]);
      emit LootBoxesDispensed(_address, _ids[i], _amounts[i]);
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
}

