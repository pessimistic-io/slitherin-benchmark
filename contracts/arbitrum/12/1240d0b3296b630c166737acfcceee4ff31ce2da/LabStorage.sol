// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ILabStorage.sol";

import "./ManagerModifier.sol";

contract LabStorage is ReentrancyGuard, Pausable, ManagerModifier, ILabStorage {
  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => mapping(uint256 => uint256)) public labs;

  //=======================================
  // Events
  //=======================================
  event Set(uint256[] realmIds, uint256[] entityIds, uint256[] amounts);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager) ManagerModifier(_manager) {}

  //=======================================
  // External
  //=======================================
  function set(
    uint256[] calldata _realmIds,
    uint256[] calldata _entityIds,
    uint256[] calldata _amounts
  ) external onlyManager {
    for (uint256 i = 0; i < _entityIds.length; i++) {
      labs[_realmIds[i]][_entityIds[i]] = _amounts[i];
    }

    emit Set(_realmIds, _entityIds, _amounts);
  }
}

