// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";
import {IAutomator} from "./IAutomator.sol";

library AutomatorUniswapV3PoolLib {
    error BurnLiquidityExceedsMint();

    function currentTick(IUniswapV3Pool pool) internal view returns (int24 tick) {
        (, tick, , , , , ) = pool.slot0();
    }

    function estimateTotalTokensFromPositions(
        IUniswapV3Pool pool,
        IAutomator.RebalanceTickInfo[] memory positions
    ) internal view returns (uint256 totalAmount0, uint256 totalAmount1) {
        uint256 _a0;
        uint256 _a1;

        (, int24 _ct, , , , , ) = pool.slot0();
        int24 _spacing = pool.tickSpacing();

        uint256 _pLen = positions.length;
        for (uint256 i = 0; i < _pLen; i++) {
            (_a0, _a1) = LiquidityAmounts.getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(_ct),
                TickMath.getSqrtRatioAtTick(positions[i].tick),
                TickMath.getSqrtRatioAtTick(positions[i].tick + _spacing),
                positions[i].liquidity
            );

            totalAmount0 += _a0;
            totalAmount1 += _a1;
        }
    }
}

