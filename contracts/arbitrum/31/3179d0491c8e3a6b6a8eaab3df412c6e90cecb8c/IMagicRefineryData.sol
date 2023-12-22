// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IMagicRefineryData {
  function data(uint256 _structureId, uint256 _traitId)
    external
    view
    returns (uint256);

  function create(
    uint256 _structureId,
    uint256 _level,
    uint256 _amountSpent
  ) external;

  function claim(uint256 _structureId) external;

  function addProperty(
    uint256 _structureId,
    uint256 _prop,
    uint256 _val
  ) external;

  function addToProperty(
    uint256 _structureId,
    uint256 _prop,
    uint256 _val
  ) external;
}

