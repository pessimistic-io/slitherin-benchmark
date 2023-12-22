// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {GelatoOps} from "./GelatoOps.sol";
import {StaticCallExecutorMock} from "./StaticCallExecutorMock.sol";

// import "forge-std/console2.sol";

contract StaticCallResolverMock {
    uint public count = 0;
    uint public lastTime = 0;
    address public gelatoExecutor;
    StaticCallExecutorMock executor;

    constructor(address _exec) {
        executor = StaticCallExecutorMock(_exec);
        gelatoExecutor = GelatoOps.getDedicatedMsgSender(msg.sender);
    }

    // @inheritdoc IResolver
    function checker() external returns (bool, bytes memory) {
        //must be called at least 30 second apart
        if (block.timestamp - executor.lastTime() >= 30) {
            uint _count = executor.incrementCounter(0);
            if (_count != executor.count() + 1) {
                return (false, bytes("Error: count not updated"));
            }
            bytes memory execPayload = abi.encodeWithSelector(StaticCallExecutorMock.incrementCounter.selector, _count);
            return (true, execPayload);
        } else {
            return (false, bytes("Error: too soon"));
        }
    }
}

