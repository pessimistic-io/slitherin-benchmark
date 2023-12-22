// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OptionMath.sol";

import "./IPremiaPool.sol";
import "./IVolatilitySurfaceOracle.sol";
import "./CumulativeNormalDistribution.sol";

import "./IPricer.sol";

/**
 * @title Knox Pricer Internal Contract
 */

contract PricerInternal {
    using ABDKMath64x64 for uint256;

    uint256 public immutable PriceUpdateThreshold;
    address public immutable Base;
    address public immutable Underlying;

    IVolatilitySurfaceOracle public immutable IVolOracle;
    AggregatorV3Interface public immutable BaseSpotOracle;
    AggregatorV3Interface public immutable UnderlyingSpotOracle;

    constructor(
        uint256 threshold,
        address pool,
        address volatilityOracle
    ) {
        PriceUpdateThreshold = threshold;

        IVolOracle = IVolatilitySurfaceOracle(volatilityOracle);

        IPremiaPool.PoolSettings memory settings =
            IPremiaPool(pool).getPoolSettings();

        Base = settings.base;
        Underlying = settings.underlying;

        BaseSpotOracle = AggregatorV3Interface(settings.baseOracle);
        UnderlyingSpotOracle = AggregatorV3Interface(settings.underlyingOracle);

        uint8 decimals = UnderlyingSpotOracle.decimals();

        require(
            BaseSpotOracle.decimals() == decimals,
            "oracle decimals must match"
        );
    }

    /**
     * @notice gets the latest price of the underlying denominated in the base
     * @return price of underlying asset as 64x64 fixed point number
     */
    function _latestAnswer64x64() internal view returns (int128) {
        (
            uint80 baseRoundID,
            int256 basePrice,
            ,
            uint256 baseUpdatedAt,
            uint80 baseAnsweredInRound
        ) = BaseSpotOracle.latestRoundData();

        (
            uint80 underlyingRoundID,
            int256 underlyingPrice,
            ,
            uint256 underlyingUpdatedAt,
            uint80 underlyingAnsweredInRound
        ) = UnderlyingSpotOracle.latestRoundData();

        require(
            baseAnsweredInRound >= baseRoundID &&
                PriceUpdateThreshold >= block.timestamp - baseUpdatedAt,
            "base: stale price"
        );

        require(basePrice > 0, "base: price <= 0");

        require(
            underlyingAnsweredInRound >= underlyingRoundID &&
                PriceUpdateThreshold >= block.timestamp - underlyingUpdatedAt,
            "underlying: stale price"
        );

        require(underlyingPrice > 0, "underlying: price <= 0");
        return ABDKMath64x64.divi(underlyingPrice, basePrice);
    }

    /**
     * @notice calculates the time remaining until maturity
     * @param expiry the expiry date as UNIX timestamp
     * @return time remaining until maturity
     */
    function _getTimeToMaturity64x64(uint64 expiry)
        internal
        view
        returns (int128)
    {
        require(expiry > block.timestamp, "block.timestamp >= expiry");
        return ABDKMath64x64.divu(expiry - block.timestamp, 365 days);
    }

    /**
     * @notice gets the annualized volatility of the pool pair
     * @param spot64x64 spot price of the underlying as 64x64 fixed point number
     * @param strike64x64 strike price of the option as 64x64 fixed point number
     * @param timeToMaturity64x64 time remaining until maturity as a 64x64 fixed point number
     * @return annualized volatility as 64x64 fixed point number
     */
    function _getAnnualizedVolatility64x64(
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) internal view returns (int128) {
        int128 annualizedVolatility64x64 =
            IVolOracle.getAnnualizedVolatility64x64(
                Base,
                Underlying,
                spot64x64,
                strike64x64,
                timeToMaturity64x64
            );

        require(annualizedVolatility64x64 > 0, "annualized volatlity <= 0");
        return annualizedVolatility64x64;
    }
}

