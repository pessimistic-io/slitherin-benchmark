// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

library Constants {
    bytes1 public constant OPERATION_NULL = 0x00;
    bytes1 public constant OPERATION_QUEUED = 0x01;
    bytes1 public constant OPERATION_EXECUTED = 0x02;
    bytes1 public constant OPERATION_CANCELLED = 0x03;
    bytes32 public constant GOVERNANCE_MESSAGE_SENTINELS = keccak256("GOVERNANCE_MESSAGE_SENTINELS");
}

