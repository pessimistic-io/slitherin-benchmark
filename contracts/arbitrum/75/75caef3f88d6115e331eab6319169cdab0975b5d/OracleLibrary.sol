// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IUniswapV3Pool.sol";

/// @title Oracle library
/// @notice Provides functions to integrate with V3 pool oracle
library OracleLibrary {
    error InvalidLength();
    error InvalidState();
    error InvalidIndex();
    error InvalidValue();

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
        if (secondsAgo == 0) revert InvalidValue();

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
        if (secondsAgo.length < 2) revert InvalidLength();
        for (uint256 i = 1; i < secondsAgo.length; i++) {
            if (secondsAgo[i] <= secondsAgo[i - 1]) revert InvalidState();
        }

        try IUniswapV3Pool(pool).observe(secondsAgo) returns (int56[] memory tickCumulatives, uint160[] memory) {
            arithmeticMeanTicks = new int24[](secondsAgo.length - 1);

            for (uint256 i = 1; i < secondsAgo.length; i++) {
                int56 tickCumulativesDelta = tickCumulatives[i] - tickCumulatives[i - 1];
                uint32 timespan = secondsAgo[i] - secondsAgo[i - 1];
                arithmeticMeanTicks[i - 1] = int24(tickCumulativesDelta / int56(uint56(timespan)));

                if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(timespan)) != 0))
                    arithmeticMeanTicks[i - 1]--;
            }
            return (arithmeticMeanTicks, false);
        } catch {
            return (new int24[](0), true);
        }
    }

    function consultByObservation(address pool, uint16 observationsAgo) internal view returns (int24) {
        if (observationsAgo == 0) revert InvalidIndex();
        uint16[] memory observationsAgos = new uint16[](2);
        observationsAgos[0] = observationsAgo;
        int24[] memory arithmeticMeanTicks = consultByObservations(pool, observationsAgos);
        return arithmeticMeanTicks[0];
    }

    function consultByObservations(
        address pool,
        uint16[] memory observationsAgos
    ) internal view returns (int24[] memory arithmeticMeanTicks) {
        if (observationsAgos.length < 2) revert InvalidLength();
        uint32[] memory secondsAgo = new uint32[](observationsAgos.length);
        int56[] memory tickCumulatives = new int56[](observationsAgos.length);

        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(pool).slot0();

        uint32 oldestObservation = (observationIndex + 1) % observationCardinality;
        uint32 newestObservation = oldestObservation + observationCardinality - 1;
        for (uint256 i = 0; i < observationsAgos.length; i++) {
            if (observationsAgos[i] >= observationCardinality) revert InvalidIndex();
            uint32 position = uint16((newestObservation - observationsAgos[i]) % observationCardinality);
            (secondsAgo[i], tickCumulatives[i], , ) = IUniswapV3Pool(pool).observations(position);
        }

        unchecked {
            arithmeticMeanTicks = new int24[](secondsAgo.length - 1);
            for (uint256 i = 1; i < secondsAgo.length; i++) {
                int56 tickCumulativesDelta = tickCumulatives[i] - tickCumulatives[i - 1];
                uint32 timespan = secondsAgo[i] - secondsAgo[i - 1];
                arithmeticMeanTicks[i - 1] = int24(tickCumulativesDelta / int56(uint56(timespan)));

                if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(timespan)) != 0))
                    arithmeticMeanTicks[i - 1]--;
            }
        }
    }
}

