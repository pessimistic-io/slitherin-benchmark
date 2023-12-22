// SPDX-License-Identifier: MIT
import "./TimelockController.sol";

pragma solidity 0.8.17;

contract GNSTimelockManager is TimelockController {
  constructor(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    address admin
  ) TimelockController(minDelay, proposers, executors, admin) {}
}
