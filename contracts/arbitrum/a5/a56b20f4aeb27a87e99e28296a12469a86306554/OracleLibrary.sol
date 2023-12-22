// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IUniswapV3Pool.sol";

/// @title Oracle library
/// @notice Provides functions to integrate with V3 pool oracle
library OracleLibrary {
    /// @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
    /// @param pool Address of the pool that we want to observe
    /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
    /// @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp
    /// @return harmonicMeanLiquidity The harmonic mean liquidity from (block.timestamp - secondsAgo) to block.timestamp
    /// @return withFail Flag that true if function observe of IUniswapV3Pool reverts with some error
    function consult(
        address pool,
        uint32 secondsAgo
    ) internal view returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity, bool withFail) {
        require(secondsAgo != 0, "BP");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        try IUniswapV3Pool(pool).observe(secondsAgos) returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        ) {
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            uint160 secondsPerLiquidityCumulativesDelta = secondsPerLiquidityCumulativeX128s[1] -
                secondsPerLiquidityCumulativeX128s[0];

            arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
            // Always round to negative infinity
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0))
                arithmeticMeanTick--;

            // We are multiplying here instead of shifting to ensure that harmonicMeanLiquidity doesn't overflow uint128
            uint192 secondsAgoX160 = uint192(secondsAgo) * type(uint160).max;
            harmonicMeanLiquidity = uint128(secondsAgoX160 / (uint192(secondsPerLiquidityCumulativesDelta) << 32));
        } catch {
            return (0, 0, true);
        }
    }

    function consultMultiple(
        address pool,
        uint32[] memory secondsAgo
    ) internal view returns (int24[] memory arithmeticMeanTicks, bool withFail) {
        require(secondsAgo.length > 0);
        for (uint256 i = 1; i < secondsAgo.length; i++) {
            require(secondsAgo[i] > secondsAgo[i - 1], "Invalid order");
        }
        require(secondsAgo[0] > 0);

        try IUniswapV3Pool(pool).observe(secondsAgo) returns (int56[] memory tickCumulatives, uint160[] memory) {
            arithmeticMeanTicks = new int24[](secondsAgo.length - 1);

            for (uint256 i = 1; i < secondsAgo.length; i++) {
                int56 tickCumulativesDelta = tickCumulatives[i] - tickCumulatives[0];
                uint32 timespan = secondsAgo[i] - secondsAgo[0];
                arithmeticMeanTicks[i - 1] = int24(tickCumulativesDelta / int56(uint56(timespan)));

                if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(timespan)) != 0))
                    arithmeticMeanTicks[i - 1]--;
            }
            return (arithmeticMeanTicks, false);
        } catch {
            return (new int24[](0), true);
        }
    }
}

