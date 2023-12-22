// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ISwapRouter {
    enum ExchangeRoute {
        SUSHI,
        UNISWAP_V3,
        CURVE
    }

    function executeSwapOutMin(
        address fromAsset,
        address toAsset,
        uint256 amountIn,
        uint256 amountOutMin,
        ExchangeRoute exchange,
        bytes memory params
    ) external returns (uint256 amountInConsumed);

    function executeSwapInMax(
        address fromAsset,
        address toAsset,
        uint256 amountInMax,
        uint256 amountOut,
        ExchangeRoute exchange,
        bytes memory params
    ) external returns (uint256 amountOutReceived);
}

