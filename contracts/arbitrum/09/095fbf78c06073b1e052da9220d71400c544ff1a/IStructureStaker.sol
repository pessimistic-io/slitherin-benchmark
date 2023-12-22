// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IStructureStaker {
  function stakeFor(
    address _staker,
    uint256 _realmId,
    address _addr,
    uint256 _structureId
  ) external;

  function unstakeFor(
    address _staker,
    uint256 _realmId,
    address _addr,
    uint256 _structureId
  ) external;

  function stakeBatchFor(
    address _staker,
    uint256[] calldata _realmIds,
    address[] calldata _addrs,
    uint256[] calldata _structureIds
  ) external;

  function unstakeBatchFor(
    address _staker,
    uint256[] calldata _realmIds,
    address[] calldata _addrs,
    uint256[] calldata _structureIds
  ) external;

  function getStaker(
    uint256 _realmId,
    address _addr,
    uint256 _structureId
  ) external;

  function hasStaked(
    uint256 _realmId,
    address _addr,
    uint256 _count
  ) external returns (bool);
}

