// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IExchangeAdapter {
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

