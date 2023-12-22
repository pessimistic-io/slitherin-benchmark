// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error ZeroAddress();

interface IPriceFacadeError {
    error NonexistentRequestId(bytes32 requestId);
}

interface ITradingCoreError {
    error UnsupportedMarginToken(address token);
}
