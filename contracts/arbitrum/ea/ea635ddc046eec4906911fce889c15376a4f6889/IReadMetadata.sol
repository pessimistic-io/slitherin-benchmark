// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IReadMetadata {
  function get(uint256 _id) external view returns (string memory metadata);
}

