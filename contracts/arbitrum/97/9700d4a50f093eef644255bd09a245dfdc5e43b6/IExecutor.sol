// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {OutInformation, Operation} from "./structs.sol";

abstract contract IExecutor {
    function execute(
        Operation[] memory routingCall, // Can't turn to calldata because of wrapper functions
        OutInformation memory outInformation // Can't turn to calldata because of wrapper functions
    ) public payable virtual;
}

