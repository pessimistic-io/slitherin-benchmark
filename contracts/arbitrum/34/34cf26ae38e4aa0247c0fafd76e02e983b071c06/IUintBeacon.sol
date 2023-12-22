// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

interface IUintBeacon {
  event UintChange(bytes32 key, uint256 value);

  function set(bytes32 key, uint256 value) external;

  function get(bytes32 key) external view returns (uint256);
}

