// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVolatilitySurfaceOracle {
    /**
     * @notice calculate the annualized volatility for given set of parameters
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param spot64x64 64x64 fixed point representation of spot price
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
     * @return 64x64 fixed point representation of annualized implied volatility, where 1 is defined as 100%
     */
    function getAnnualizedVolatility64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) external view returns (int128);

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @param base The base token of the pair
     * @param underlying The underlying token of the pair
     * @param spot64x64 Spot price, as a 64x64 fixed point representation
     * @param strike64x64 Strike, as a64x64 fixed point representation
     * @param timeToMaturity64x64 64x64 fixed point representation of time to maturity (denominated in years)
     * @param isCall Whether it is for call or put
     * @return 64x64 fixed point representation of the Black Scholes price
     */
    function getBlackScholesPrice64x64(
        address base,
        address underlying,
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (int128);
}

