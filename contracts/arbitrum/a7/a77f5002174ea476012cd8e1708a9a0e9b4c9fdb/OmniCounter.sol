// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

import "./NonblockingLzApp.sol";

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
contract OmniCounter is NonblockingLzApp {
    uint public counter;

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {}

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal override {
        counter++;
    }

    function incrementCounter(uint16 _dstChainId) public payable {
        counter++;
        _lzSend(_dstChainId, bytes(""), payable(msg.sender), address(0x0), "", msg.value);
    }
}

