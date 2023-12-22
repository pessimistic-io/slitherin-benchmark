// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PricerInternal.sol";

/**
 * @title Knox Pricer Contract
 * @dev deployed standalone
 */

contract Pricer is IPricer, PricerInternal {
    using ABDKMath64x64 for int128;
    using OptionMath for int128;
    using CumulativeNormalDistribution for int128;

    int128 private constant ONE_64x64 = 0x10000000000000000;

    constructor(
        uint256 threshold,
        address pool,
        address volatilityOracle
    ) PricerInternal(threshold, pool, volatilityOracle) {}

    /**
     * @inheritdoc IPricer
     */
    function latestAnswer64x64() external view returns (int128) {
        return _latestAnswer64x64();
    }

    /**
     * @inheritdoc IPricer
     */
    function getTimeToMaturity64x64(uint64 expiry)
        external
        view
        returns (int128)
    {
        return _getTimeToMaturity64x64(expiry);
    }

    /**
     * @inheritdoc IPricer
     */
    function getAnnualizedVolatility64x64(
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64
    ) external view returns (int128) {
        return
            _getAnnualizedVolatility64x64(
                spot64x64,
                strike64x64,
                timeToMaturity64x64
            );
    }

    /**
     * @inheritdoc IPricer
     */
    function getBlackScholesPrice64x64(
        int128 spot64x64,
        int128 strike64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) external view returns (int128) {
        return
            IVolOracle.getBlackScholesPrice64x64(
                Base,
                Underlying,
                spot64x64,
                strike64x64,
                timeToMaturity64x64,
                isCall
            );
    }

    /**
     * @inheritdoc IPricer
     */
    function getDeltaStrikePrice64x64(
        bool isCall,
        uint64 expiry,
        int128 delta64x64
    ) external view returns (int128) {
        int128 spot64x64 = _latestAnswer64x64();
        int128 timeToMaturity64x64 = _getTimeToMaturity64x64(expiry);

        int128 ivATM64x64 =
            _getAnnualizedVolatility64x64(
                spot64x64,
                spot64x64,
                timeToMaturity64x64
            );

        int128 v = ivATM64x64.mul(timeToMaturity64x64.sqrt());
        int128 w = timeToMaturity64x64.mul(ivATM64x64.pow(2)) >> 1;

        if (!isCall) delta64x64 = ONE_64x64.sub(delta64x64);
        int128 beta = delta64x64.getInverseCDF();

        int128 z = w.sub(beta.mul(v));
        int128 strike64x64 = spot64x64.mul(z.exp());

        require(strike64x64 > 0, "strike64x64 <= 0");
        return strike64x64;
    }

    /**
     * @inheritdoc IPricer
     */
    function snapToGrid64x64(bool isCall, int128 n)
        external
        pure
        returns (int128)
    {
        return isCall ? n.ceil64x64() : n.floor64x64();
    }
}

