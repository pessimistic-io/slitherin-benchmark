// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IHandler {
    function handleReceive(address target, bytes calldata payload) external;
    function handleSend(address target, bytes calldata payload) external;
}
