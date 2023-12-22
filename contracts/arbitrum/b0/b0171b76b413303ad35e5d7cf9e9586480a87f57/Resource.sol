// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ReentrancyGuard.sol";
import "./ManagerModifier.sol";

contract Resource is ReentrancyGuard, ManagerModifier {
  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => mapping(uint256 => uint256)) public data;

  //=======================================
  // Events
  //=======================================
  event Added(
    uint256 realmId,
    uint256 resourceId,
    uint256 amount,
    uint256 totalAmount
  );
  event Removed(
    uint256 realmId,
    uint256 resourceId,
    uint256 amount,
    uint256 totalAmount
  );

  constructor(address _manager) ManagerModifier(_manager) {}

  function add(
    uint256 _realmId,
    uint256 _resourceId,
    uint256 _amount
  ) external nonReentrant onlyManager {
    data[_realmId][_resourceId] += _amount;

    emit Added(_realmId, _resourceId, _amount, data[_realmId][_resourceId]);
  }

  function remove(
    uint256 _realmId,
    uint256 _resourceId,
    uint256 _amount
  ) external nonReentrant onlyManager {
    require(
      _amount <= data[_realmId][_resourceId],
      "Resource: Not enough resources"
    );

    data[_realmId][_resourceId] -= _amount;

    emit Removed(_realmId, _resourceId, _amount, data[_realmId][_resourceId]);
  }
}

