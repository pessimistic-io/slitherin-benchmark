// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IUniswapV3Twap {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function pool() external view returns (address);

    function estimateAmountOut(
        address tokenIn,
        uint128 amountIn,
        uint32 secondsAgo
    ) external view returns (uint amountOut);
}

