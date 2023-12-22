// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IManager.sol";
import "./ManagerModifier.sol";

contract MagicRefineryData is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => mapping(uint256 => uint256)) public data;
  mapping(uint256 => bool) public claimed;

  //=======================================
  // Int
  //=======================================
  uint256 public dataLength;

  //=======================================
  // Events
  //=======================================
  event Created(uint256 structureId, uint256 level, uint256 amountSpent);
  event PropertyAdded(uint256 structureId, uint256 prop, uint256 value);
  event PropertyAddedTo(uint256 structureId, uint256 prop, uint256 value);
  event Claimed(uint256 structureId);

  //=======================================
  // Constructor
  //=======================================
  constructor(address _manager, uint256 _dataLength) ManagerModifier(_manager) {
    dataLength = _dataLength;
  }

  //=======================================
  // External
  //=======================================
  function create(
    uint256 _structureId,
    uint256 _level,
    uint256 _amountSpent
  ) external onlyManager {
    data[_structureId][0] = _level; // level
    data[_structureId][1] = _amountSpent; // amount spent
    data[_structureId][2] = block.timestamp; // createdAt

    emit Created(_structureId, _level, _amountSpent);
  }

  function getData(uint256 _structureId)
    external
    view
    returns (uint256[] memory)
  {
    uint256 j = 0;
    uint256[] memory arr = new uint256[](dataLength);

    for (; j < dataLength; j++) {
      arr[j] = data[_structureId][j];
    }

    return arr;
  }

  function claim(uint256 _structureId) external onlyManager {
    claimed[_structureId] = true;

    emit Claimed(_structureId);
  }

  function addProperty(
    uint256 _structureId,
    uint256 _prop,
    uint256 _val
  ) external onlyManager {
    data[_structureId][_prop] = _val;

    emit PropertyAdded(_structureId, _prop, _val);
  }

  function addToProperty(
    uint256 _structureId,
    uint256 _prop,
    uint256 _val
  ) external onlyManager {
    data[_structureId][_prop] += _val;

    emit PropertyAddedTo(_structureId, _prop, _val);
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

  function updateDataLength(uint256 _dataLength) external onlyAdmin {
    dataLength = _dataLength;
  }
}

