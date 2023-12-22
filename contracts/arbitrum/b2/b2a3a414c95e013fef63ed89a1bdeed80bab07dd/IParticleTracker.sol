// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IParticleTracker {
  function timer(address _addr, uint256 _adventurerId)
    external
    view
    returns (uint256);

  function currentRealm(address _addr, uint256 _adventurerId)
    external
    view
    returns (uint256, bool);

  function getExplorerCount(uint256 _realmId) external view returns (uint256);

  function addExplorer(
    uint256 _realmId,
    address _addr,
    uint256 _adventurerId,
    uint256 _amount
  ) external;

  function removeExplorer(
    uint256 _realmId,
    address _addr,
    uint256 _adventurerId,
    uint256 _amount
  ) external;

  function setTimer(address _addr, uint256 _adventurerId) external;
}

