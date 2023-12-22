// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IAovLegacy {
  function chronicle(
    address _addr,
    uint256 _adventurerId,
    uint256 _currentArchetype,
    uint256 _archetype
  ) external;
}

