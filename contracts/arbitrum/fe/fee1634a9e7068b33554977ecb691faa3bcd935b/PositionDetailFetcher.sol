// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "./LiquidityAmounts.sol";
import "./TickMath.sol";

contract PositionDetailFetcher {
    function calculateAmounts(int24 tickLower, int24 tickUpper, uint128 liquidity, uint160 sqrtPriceX96) public pure returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }
}

