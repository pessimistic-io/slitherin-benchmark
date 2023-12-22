// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <0.9.0;

import "./console.sol";
import "./FullMath.sol";
import "./TickMath.sol";
import {IPool} from "./IPool.sol";
import {IPoolOracle} from "./IPoolOracle.sol";


/// @title Oracle library
/// @notice Provides functions to integrate with Kyberswap pool oracle
library OracleLibrary {
    /// @notice Calculates arithmetic TWAPs for a given Kyberswap pool
    /// @param poolOracle Address of the pool oracle that we want to use to observe pool
    /// @param pool Address of the pool that we want to observe
    /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
    /// @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp
    function consult(address poolOracle, address pool, uint32 secondsAgo)
        internal
        view
        returns (int24 arithmeticMeanTick)
    {
        require(secondsAgo != 0, "BP");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (
            int56[] memory tickCumulatives
        ) = IPoolOracle(poolOracle).observeFromPool(pool, secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        arithmeticMeanTick = int24(
            tickCumulativesDelta / int56(uint56(secondsAgo))
        );
        // Always round to negative infinity
        if (
            tickCumulativesDelta < 0 &&
            (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)
        ) arithmeticMeanTick--;
    }

    /// @notice Given a pool, it returns the number of seconds ago of the oldest stored observation
    /// @param poolOracle Address of the pool oracle that we want to use to observe pool
    /// @param pool Address of the pool that we want to observe
    /// @return secondsAgo The number of seconds ago of the oldest observation stored for the pool
    function getOldestObservationSecondsAgo(address poolOracle, address pool)
        internal
        view
        returns (uint32 secondsAgo)
    {
        (
            ,
            uint16 observationIndex,
            uint16 observationCardinality,
        ) = IPoolOracle(poolOracle).getPoolObservation(pool);
        require(observationCardinality > 0, "NI");

        (uint32 observationTimestamp, , bool initialized) = IPoolOracle(poolOracle).getObservationAt(
            pool, 
            (observationIndex + 1) % observationCardinality
        );

        // The next index might not be initialized if the cardinality is in the process of increasing
        // In this case the oldest observation is always in index 0
        if (!initialized) {
            (observationTimestamp, , ) = IPoolOracle(poolOracle).getObservationAt(pool, 0);
        }

        unchecked {
            secondsAgo = uint32(block.timestamp) - observationTimestamp;
        }
    }

}

