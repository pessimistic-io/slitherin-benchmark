// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./TimelockController.sol";

contract MockTimelockController is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {
    }
}

