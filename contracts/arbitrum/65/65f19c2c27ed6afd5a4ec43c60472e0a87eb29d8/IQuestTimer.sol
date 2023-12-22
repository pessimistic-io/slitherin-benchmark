// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IQuestTimer {
  function set(
    address _addr,
    uint256 _adventurerId,
    uint256 _questCount,
    uint256 _hours
  ) external;

  function canQuest(address _addr, uint256 _adventurerId)
    external
    view
    returns (bool);
}

