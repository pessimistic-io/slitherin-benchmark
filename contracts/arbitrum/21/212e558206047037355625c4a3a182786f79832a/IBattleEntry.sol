// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./Pausable.sol";

import "./ManagerModifier.sol";

enum BattleEntryEligibility {
  ELIGIBLE,
  INELIGIBLE,
  UNINITIALIZED
}

interface IBattleEntry {
  //=======================================
  // External
  //=======================================
  function set(address _addr, uint256 _id) external;

  function isEligible(
    address _oppAddr,
    uint256 _oppId
  ) external view returns (BattleEntryEligibility);
}

