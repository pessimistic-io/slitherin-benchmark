// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ISwapHelper {
    error SwapFailed();

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address router,
        bytes calldata routerCalldata
    ) external returns (uint256 amountOut);
}

