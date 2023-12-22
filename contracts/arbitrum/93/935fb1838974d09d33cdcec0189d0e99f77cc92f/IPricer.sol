// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AggregatorV3Interface.sol";

/**
 * @title Knox Pricer Interface
 */

interface IPricer {
    /**
     * @notice gets the latest price of the underlying denominated in the base
     * @return price of underlying asset as 64x64 fixed point number
     */
    function latestAnswer64x64() external view returns (int128);

    /**
     * @notice calculates the time remaining until maturity
     * @param expiry the expiry date as UNIX timestamp
     * @return time remaining until maturity
     */
    function getTimeToMaturity64x64(uint64 expiry)
        external
        view
        returns (int128);

    /**
     * @notice gets the annualized volatility of the pool pair
     * @param spot64x64 spot price of the underlying as 64x64 fixed point number
     * @param strike64x64 strike price of the option as 64x64 fixed point number
     * @param timeToMaturity64x64 time remaining until maturity as a 64x64 fixed point number
     * @return annualized volatility as 64x64 fixed point number
     */
    function getAnnualizedVolatility64x64(
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) external view returns (int128);

    /**
     * @notice gets the option price using the Black-Scholes model
     * @param spot64x64 spot price of the underlying as 64x64 fixed point number
     * @param strike64x64 strike price of the option as 64x64 fixed point number
     * @param timeToMaturity64x64 time remaining until maturity as a 64x64 fixed point number
     * @param isCall option type, true if call option
     * @return price of the option denominated in the base as 64x64 fixed point number
     */
    function getBlackScholesPrice64x64(
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (int128);

    /**
     * @notice calculates the delta strike price
     * @param isCall option type, true if call option
     * @param expiry the expiry date as UNIX timestamp
     * @param delta64x64 option delta as 64x64 fixed point number
     * @return delta strike price as 64x64 fixed point number
     */
    function getDeltaStrikePrice64x64(
        bool isCall,
        uint64 expiry,
        int128 delta64x64
    ) external view returns (int128);

    /**
     * @notice rounds a value to the floor or ceiling depending on option type
     * @param isCall option type, true if call option
     * @param n input value
     * @return rounded value as 64x64 fixed point number
     */
    function snapToGrid64x64(bool isCall, int128 n)
        external
        view
        returns (int128);
}

