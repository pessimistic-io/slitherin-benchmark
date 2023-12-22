// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @title Handles ERC20 deposits and deposit executions.
/// @author Router Protocol.
/// @notice This contract is intended to be used with the Bridge contract.
interface IMessageHandler {
    function handleMessage(
        address tokenSent,
        uint256 amount,
        bytes memory message
    ) external;
}

