// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;


contract one {
    event Sender(address indexed sender);
    function emitEvent() external{
        emit Sender(msg.sender);
    }
}