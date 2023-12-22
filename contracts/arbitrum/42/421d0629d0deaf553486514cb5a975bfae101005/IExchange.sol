// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IExchange {
    // TraderJoe Interfaces
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) external view returns (uint256[] memory amounts);
}

interface IJoeLiquidityBook {
    // TraderJoe Liquidity Book Interfaces
    function getSwapOut(
        address pair,
        uint256 amountIn,
        bool swapForY
    ) external view returns (uint256 amountOut, uint256 feesIn);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

