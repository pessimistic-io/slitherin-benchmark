// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMessageTransmitter {
    function receiveMessage(
        bytes calldata message,
        bytes calldata signature
    ) external returns (bool success);

    function sendMessageWithCaller(
        uint32 destinationDomain,
        bytes32 recipient,
        bytes32 destinationCaller,
        bytes calldata messageBody
    ) external returns (uint64);
}

