// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Pausable.sol";

import "./ManagerModifier.sol";

interface IBattleEntry {
  //=======================================
  // External
  //=======================================
  function set(address _addr, uint256 _id) external;

  function isEligible(address _oppAddr, uint256 _oppId) external returns (bool);
}

