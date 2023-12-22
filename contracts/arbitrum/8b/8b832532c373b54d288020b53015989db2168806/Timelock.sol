// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { TimelockController } from "./TimelockController.sol";

contract Timelock is TimelockController {
    constructor(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors,
        address admin
    ) TimelockController(_minDelay, _proposers, _executors, admin) {}
}

