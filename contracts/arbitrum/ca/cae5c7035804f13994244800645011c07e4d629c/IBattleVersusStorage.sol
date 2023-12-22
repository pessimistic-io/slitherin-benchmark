// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IBattleVersusStorage {
  function setAttackerCooldown(
    address _addr,
    uint256 _adventurerId,
    uint256 _hours
  ) external;

  function setOpponentCooldown(
    address _addr,
    uint256 _adventurerId,
    uint256 _hours
  ) external;

  function updateWins(
    address _addr,
    uint256 _adventurerId,
    uint256 wins
  ) external;

  function updateLosses(
    address _addr,
    uint256 _adventurerId,
    uint256 losses
  ) external;
}

