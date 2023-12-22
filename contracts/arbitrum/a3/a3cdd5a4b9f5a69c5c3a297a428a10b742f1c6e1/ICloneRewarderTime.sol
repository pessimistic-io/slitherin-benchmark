// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ICloneRewarderTime {
  function pendingToken(
    uint256 pid,
    address user
  ) external view returns (uint256);
}

