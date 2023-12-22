// SPDX-License-Identifier: UNLICENSED
// Copyright (c) Eywa.Fi, 2021-2023 - all rights reserved
pragma solidity 0.8.17;

import "./BridgeV2.sol";

contract TestEmit is BridgeV2 {
    event TestEvent(bytes32 indexed id, address indexed who, string what, uint256 when);

    function testTestEvent(bytes32 id, string calldata what) public {
        address who = address(this);
        emit TestEvent(id, who, what, block.timestamp);
    }

    function testRequestSent(bytes32 requestId, bytes memory selector) public {
        address bridge = address(this);
        uint64 chain = 0xCAFEBABE;
        emit RequestSent(requestId, selector, bridge, chain);
    }

    function testRequestReceived(bytes32 requestId, bytes32 bridgeFrom) public {
        address bridge = address(this);
        emit RequestReceived(requestId, "");
    }
}

