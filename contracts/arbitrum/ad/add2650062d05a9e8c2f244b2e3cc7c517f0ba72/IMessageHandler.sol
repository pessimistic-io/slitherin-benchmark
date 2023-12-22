// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IMessageHandler {
    function handleReceiveMessage(
        uint32 sourceDomain,
        bytes32 sender,
        bytes calldata messageBody
    ) external returns (bool);
}

