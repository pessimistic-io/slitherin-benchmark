// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {OracleLibrary} from "./OracleLibrary.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IERC20Detailed} from "./IERC20Detailed.sol";
import {FullMath} from "./FullMath.sol";
import {TickMath} from "./TickMath.sol";
import {FixedPoint96} from "./FixedPoint96.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {X96Math} from "./X96Math.sol";
import {DataTypes} from "./DataTypes.sol";
import {Errors} from "./Errors.sol";

import "./console.sol";

/**
 * @title Uniswap v3 Dex Oracle Logic library
 * @author Tazz Labs
 * @notice Implements the logic to read current prices from Uniswap V3 Dexs for internal Guild purposes
 * @dev prices are returned with RAY decimal units (vs uniswap convention of quote token decimal units)
 */

library DexOracleLogic {
    using WadRayMath for uint256;

    /**
     * @notice Initializes a DexOracle structure
     * @param dexOracle The dexOracle object
     * @param assetTokenAddress The address of the underlying asset token contract (zToken)
     * @param moneyAddress The address of the money token on which the debt is denominated in
     * @param fee The fee of the pool
     **/
    function init(
        DataTypes.DexOracleData storage dexOracle,
        address dexFactory,
        address assetTokenAddress,
        address moneyAddress,
        uint24 fee
    ) internal {
        require(dexOracle.dex.token0 == address(0), Errors.DEX_ORACLE_ALREADY_INITIALIZED);
        dexOracle.dexFactory = dexFactory;

        //initialize pool info
        dexOracle.dex.token0 = assetTokenAddress;
        dexOracle.dex.token1 = moneyAddress;
        dexOracle.dex.fee = fee;

        //keep track on whether token0 is the money token
        dexOracle.dex.moneyIsToken0 = (dexOracle.dex.token1 < dexOracle.dex.token0);
        if (dexOracle.dex.moneyIsToken0)
            (dexOracle.dex.token0, dexOracle.dex.token1) = (dexOracle.dex.token1, dexOracle.dex.token0);

        //initialize the oracle historical price.  Assumes the dex pool has already be created, otherwise reverts
        address poolAddress = IUniswapV3Factory(dexFactory).getPool(
            dexOracle.dex.token0,
            dexOracle.dex.token1,
            dexOracle.dex.fee
        );
        require(poolAddress != address(0), Errors.DEX_ORACLE_POOL_NOT_INITIALIZED);
        dexOracle.dex.poolAddress = poolAddress;

        //perform initial oracle consult, to intialize TWAP trackers
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0; //get current values
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = IUniswapV3Pool(
            poolAddress
        ).observe(secondsAgos);
        dexOracle.lastTWAPTickCumulative = tickCumulatives[0];
        dexOracle.lastTWAPObservationTime = block.timestamp;
    }

    //@Dev - requires cardinality of DEX to be set, to ensure enough historical datapoints to calculated TWAP for _secondsago
    //@Dev - price returned with 27 DECIMAL precision (instead of money precision)
    function getPrice(DataTypes.DexOracleData storage dexOracle, uint32 _secondsAgo)
        internal
        view
        returns (uint256 assetPrice_)
    {
        // Get Dex Price
        address pool = dexOracle.dex.poolAddress;
        uint160 sqrtPriceX96;
        if (_secondsAgo > 0) {
            (int24 tickAvgPrice, ) = OracleLibrary.consult(pool, _secondsAgo);
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tickAvgPrice);
        } else {
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        }

        //convert to price with correct units
        assetPrice_ = _getPriceFromSqrtX96(dexOracle.dex, sqrtPriceX96);

        return assetPrice_;
    }

    //@Dev - does not require DEX cardinality greater than 1.  Variables are tracked internally
    //@Dev - relies on code found in @uniswap/v3-core/libraries/OracleLibrary.sol
    //@Dev - price returned with 27 DECIMAL precision (instead of money precision)
    function updateTWAPPrice(DataTypes.DexOracleData storage dexOracle)
        internal
        returns (uint256 assetPrice_, uint256 elapsedTime_)
    {
        uint160 sqrtPriceX96;
        int56 currentTickCumulative;
        uint256 currentObservationTime = block.timestamp;
        bool updateTWAP = (currentObservationTime > dexOracle.lastTWAPObservationTime);

        //get sqrtPrice and elapsedTime
        if (updateTWAP) {
            elapsedTime_ = currentObservationTime - dexOracle.lastTWAPObservationTime;

            //get current cumulators
            uint32[] memory secondsAgos = new uint32[](1);
            secondsAgos[0] = 0; //get current values
            (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = IUniswapV3Pool(
                dexOracle.dex.poolAddress
            ).observe(secondsAgos);
            currentTickCumulative = tickCumulatives[0];

            //calculate TWAP tick since last observation (extracted from Uniswap core v3 OracleLibrary)
            int56 tickCumulativesDelta = currentTickCumulative - dexOracle.lastTWAPTickCumulative;

            int24 arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(elapsedTime_)));
            // Always round to negative infinity
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(elapsedTime_)) != 0))
                arithmeticMeanTick--;

            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        } else {
            elapsedTime_ = 0;
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(dexOracle.dex.poolAddress).slot0();
        }

        //convert to price with correct units
        assetPrice_ = _getPriceFromSqrtX96(dexOracle.dex, sqrtPriceX96);

        if (updateTWAP) {
            //save new observations
            dexOracle.lastTWAPTickCumulative = currentTickCumulative;
            dexOracle.lastTWAPObservationTime = currentObservationTime;
            dexOracle.TWAPPrice = assetPrice_;
            dexOracle.lastTWAPTimeDelta = elapsedTime_;
        }

        return (assetPrice_, elapsedTime_);
    }

    //@Dev - price returned with RAY 27 DECIMAL precision (instead of money precision)
    function _getPriceFromSqrtX96(DataTypes.DexPoolData storage dex, uint160 sqrtRatioX96)
        internal
        view
        returns (uint256 price_)
    {
        uint256 baseDecimals = 27;
        if (dex.moneyIsToken0) {
            price_ = X96Math.getPriceFromSqrtX96(dex.token0, dex.token1, sqrtRatioX96);
            baseDecimals -= IERC20Detailed(dex.token0).decimals();
        } else {
            price_ = X96Math.getPriceFromSqrtX96(dex.token1, dex.token0, sqrtRatioX96);
            baseDecimals -= IERC20Detailed(dex.token1).decimals();
        }
        price_ *= 10**baseDecimals;
        return price_;
    }
}

