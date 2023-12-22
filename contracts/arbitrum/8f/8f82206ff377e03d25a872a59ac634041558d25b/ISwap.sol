// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface ISwap {
    function swapExactInputSingle(
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        address recipient
    ) external returns (bool, uint256);

    function swapExactOutputSingle(
        uint256 amountOut,
        uint256 amountInMaximum,
        address tokenIn,
        address tokenOut,
        address recipient
    ) external returns (bool, uint256);

    function getTokenPrice(address token) external view returns (uint256);
}

