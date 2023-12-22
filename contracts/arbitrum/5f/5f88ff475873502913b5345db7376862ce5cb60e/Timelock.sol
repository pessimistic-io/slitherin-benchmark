//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./TimelockController.sol";

contract Timelock is TimelockController {
    constructor(address[] memory _proposers, address[] memory _executors) TimelockController(3 days, _proposers, _executors, address(0)) {}
}

