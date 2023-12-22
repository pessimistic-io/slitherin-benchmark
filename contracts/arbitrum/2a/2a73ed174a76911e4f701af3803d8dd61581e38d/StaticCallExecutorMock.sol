// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

// import "forge-std/console2.sol";
import {GelatoOps} from "./GelatoOps.sol";

contract StaticCallExecutorMock {
    uint public count = 0;
    uint public lastTime = 0;
    address public gelatoExecutor;

    constructor() {
        gelatoExecutor = GelatoOps.getDedicatedMsgSender(msg.sender);
    }

    function incrementCounter(uint _minCount) external returns (uint256) {
        //require msg.sender == gelatoExecutor
        require(msg.sender == gelatoExecutor, "msg.sender != gelatoExecutor");

        uint _count = count + 1;
        require(_count >= _minCount, "count < minCount");
        count = _count;
        lastTime = block.timestamp;
        return count;
    }
}

