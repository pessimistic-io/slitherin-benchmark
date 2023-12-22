// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import "./ABDKMath64x64.sol";
import {TickMath} from "./TickMath.sol";

library TickLib {
    function getFeeGrowthInside(
        address _pool,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        unchecked {
            IUniswapV3Pool pool = IUniswapV3Pool(_pool);

            (,, uint256 lowerfeeGrowthOutside0X128, uint256 lowerfeeGrowthOutside1X128,,,,) = pool.ticks(tickLower);
            (,, uint256 upperfeeGrowthOutside0X128, uint256 upperfeeGrowthOutside1X128,,,,) = pool.ticks(tickUpper);

            // calculate fee growth below
            uint256 feeGrowthBelow0X128;
            uint256 feeGrowthBelow1X128;
            if (tickCurrent >= tickLower) {
                feeGrowthBelow0X128 = lowerfeeGrowthOutside0X128;
                feeGrowthBelow1X128 = lowerfeeGrowthOutside1X128;
            } else {
                feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lowerfeeGrowthOutside0X128;
                feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lowerfeeGrowthOutside1X128;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove0X128;
            uint256 feeGrowthAbove1X128;
            if (tickCurrent < tickUpper) {
                feeGrowthAbove0X128 = upperfeeGrowthOutside0X128;
                feeGrowthAbove1X128 = upperfeeGrowthOutside1X128;
            } else {
                feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upperfeeGrowthOutside0X128;
                feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upperfeeGrowthOutside1X128;
            }

            feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
            feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
        }
    }

    function nearestUsableTick(int24 tick_, int24 tickSpacing) internal pure returns (int24 result) {
        result = int24(divRound(int128(tick_), int128(tickSpacing))) * tickSpacing;

        if (result < TickMath.MIN_TICK) {
            result += tickSpacing;
        } else if (result > TickMath.MAX_TICK) {
            result -= tickSpacing;
        }
    }

    function divRound(int128 x, int128 y) internal pure returns (int128 result) {
        int128 quot = ABDKMath64x64.div(x, y);
        result = quot >> 64;

        // Check if remainder is greater than 0.5
        if (quot % 2 ** 64 >= 0x8000000000000000) {
            result += 1;
        }
    }
}

