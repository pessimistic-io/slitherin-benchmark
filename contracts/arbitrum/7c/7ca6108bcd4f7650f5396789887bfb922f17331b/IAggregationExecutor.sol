// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Interface for making arbitrary calls during swap
interface IAggregationExecutor {
    /// @notice propagates information about original msg.sender and executes arbitrary data
    function execute(address msgSender) external payable;

    function callBytes(bytes calldata data, address srcSpender) external payable; // 0xd9c45357
}

