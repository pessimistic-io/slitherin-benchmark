// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBridgeAdapter {
    /* Limitations:
    1. sender and recipient must have same addresses
    2. could send only to EVM chain
    3. recipient must implement ITokenWithMessageReceiver
    */

    struct Token {
        address address_;
        uint256 amount;
        uint256 slippage;
    }

    struct Message {
        uint256 dstChainId;
        bytes content;
        bytes bridgeParams;
    }

    event BridgeFinished(
        bytes32 indexed traceId,
        address token,
        uint256 amount
    );

    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token);

    function sendTokenWithMessage(
        Token calldata token,
        Message calldata message
    ) external payable returns (bytes32 traceId);

    function estimateFee(
        Token calldata token,
        Message calldata message
    ) external view returns (uint256);
}

