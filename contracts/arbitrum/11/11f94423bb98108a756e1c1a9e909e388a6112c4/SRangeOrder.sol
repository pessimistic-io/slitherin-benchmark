// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import {     IUniswapV3Pool } from "./IUniswapV3Pool.sol";

struct RangeOrderParams {
    IUniswapV3Pool pool;
    bool zeroForOne;
    bool ejectDust;
    int24 tickThreshold;
    uint256 amountIn;
    uint256 minAmountOut;
    address receiver;
    uint256 maxFeeAmount;
}

