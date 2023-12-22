// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TimelockController.sol";

contract PatrickTimeLock is TimelockController {
  // minDelay is how long you have to wait before executing
  // proposers is the list of addresses that can propose
  // executors is the list of addresses that can execute
  uint256 public constant VERSION = 1;

  constructor(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors
  ) TimelockController(minDelay, proposers, executors) {}
}

