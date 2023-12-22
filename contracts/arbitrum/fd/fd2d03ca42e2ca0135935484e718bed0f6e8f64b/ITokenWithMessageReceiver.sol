// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITokenWithMessageReceiver {
    function receiveTokenWithMessage(
        address token,
        uint256 amount,
        bytes calldata message
    ) external;
}

