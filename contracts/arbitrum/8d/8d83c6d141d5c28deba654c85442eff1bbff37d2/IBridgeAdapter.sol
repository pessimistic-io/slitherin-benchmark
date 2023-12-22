// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBridgeAdapter {
    error UnsupportedChain(uint256 chainId);
    error UnsupportedToken(address token);

    struct GeneralParams {
        address reciever;
        uint256 recieverId;
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

