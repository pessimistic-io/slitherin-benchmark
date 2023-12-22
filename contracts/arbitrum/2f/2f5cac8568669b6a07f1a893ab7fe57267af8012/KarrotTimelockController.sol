//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./TimelockController.sol";

contract KarrotTimelock is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors, msg.sender) {}
}

