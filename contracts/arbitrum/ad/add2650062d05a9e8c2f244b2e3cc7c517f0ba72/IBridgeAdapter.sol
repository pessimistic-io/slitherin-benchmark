// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBridgeAdapter {
    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token);

    event BridgeStarted(bytes32 indexed traceId);
    event BridgeFinished(
        bytes32 indexed traceId,
        address token,
        uint256 amount
    );

    struct GeneralParams {
        address fundsCollector;
        address withdrawalAddress;
        address owner;
        uint256 chainId;
        bytes bridgeParams;
    }

    struct SendTokenParams {
        address token;
        uint256 amount;
        uint256 slippage; // bps
    }

    function bridgeToken(
        GeneralParams memory generalParams,
        SendTokenParams memory sendTokenParams
    ) external payable;

    function estimateBridgeFee(
        GeneralParams memory generalParams,
        SendTokenParams memory sendTokenParams
    ) external view returns (uint256);
}

