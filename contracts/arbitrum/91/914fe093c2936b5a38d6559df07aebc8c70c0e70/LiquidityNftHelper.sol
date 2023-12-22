// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./INonfungiblePositionManager.sol";
import "./TickMath.sol";
import "./PoolHelper.sol";
import "./SafeMath.sol";

library LiquidityNftHelper {
    using SafeMath for uint256;

    function getLiquidityAmountByNftId(
        uint256 liquidityNftId,
        address nonfungiblePositionManagerAddress
    ) internal view returns (uint128 liquidity) {
        (, , , , , , , liquidity, , , , ) = INonfungiblePositionManager(
            nonfungiblePositionManagerAddress
        ).positions(liquidityNftId);
    }

    function getPoolInfoByLiquidityNft(
        uint256 liquidityNftId,
        address uniswapV3FactoryAddress,
        address nonfungiblePositionManagerAddress
    )
        internal
        view
        returns (
            address poolAddress,
            int24 tick,
            uint160 sqrtPriceX96,
            uint256 decimal0,
            uint256 decimal1
        )
    {
        (
            address token0,
            address token1,
            uint24 poolFee,
            ,
            ,
            ,

        ) = getLiquidityNftPositionsInfo(
                liquidityNftId,
                nonfungiblePositionManagerAddress
            );
        poolAddress = PoolHelper.getPoolAddress(
            uniswapV3FactoryAddress,
            token0,
            token1,
            poolFee
        );
        (, , , tick, sqrtPriceX96, decimal0, decimal1) = PoolHelper.getPoolInfo(
            poolAddress
        );
    }

    function getLiquidityNftPositionsInfo(
        uint256 liquidityNftId,
        address nonfungiblePositionManagerAddress
    )
        internal
        view
        returns (
            address token0,
            address token1,
            uint24 poolFee,
            int24 tickLower,
            int24 tickUpper,
            uint160 sqrtRatioAX96,
            uint160 sqrtRatioBX96
        )
    {
        (
            ,
            ,
            token0,
            token1,
            poolFee,
            tickLower,
            tickUpper,
            ,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(nonfungiblePositionManagerAddress)
            .positions(liquidityNftId);
        sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    }

    /// @dev formula explanation
    /*
    [Original formula (without decimal precision)]
    tickUpper -> sqrtRatioBX96
    tickLower -> sqrtRatioAX96
    tick      -> sqrtPriceX96
    (token1 * (10^decimal1)) / (token0 * (10^decimal0)) = 
        (sqrtPriceX96 * sqrtRatioBX96 * (sqrtPriceX96 - sqrtRatioAX96))
            / ((2^192) * (sqrtRatioBX96 - sqrtPriceX96))
    
    [Formula with decimal precision & decimal adjustment]
    liquidityRatioWithDecimalAdj = liquidityRatio * (10^decimalPrecision)
        = (sqrtPriceX96 * (10^decimalPrecision) / (2^96))
            * (sqrtPriceBX96 * (10^decimalPrecision) / (2^96))
            * (sqrtPriceX96 - sqrtRatioAX96)
            / ((sqrtRatioBX96 - sqrtPriceX96) * (10^(decimalPrecision + decimal1 - decimal0)))
    */
    function getInRangeLiquidityRatioWithDecimals(
        uint256 liquidityNftId,
        uint256 decimalPrecision,
        address uniswapV3FactoryAddress,
        address nonfungiblePositionManagerAddress
    ) internal view returns (uint256 liquidityRatioWithDecimals) {
        // get sqrtPrice of tickUpper, tick, tickLower
        (
            ,
            ,
            ,
            ,
            ,
            uint160 sqrtRatioAX96,
            uint160 sqrtRatioBX96
        ) = getLiquidityNftPositionsInfo(
                liquidityNftId,
                nonfungiblePositionManagerAddress
            );
        (
            ,
            ,
            uint160 sqrtPriceX96,
            uint256 decimal0,
            uint256 decimal1
        ) = getPoolInfoByLiquidityNft(
                liquidityNftId,
                uniswapV3FactoryAddress,
                nonfungiblePositionManagerAddress
            );

        // when decimalPrecision is 18,
        // calculation restriction: 79228162514264337594 <= sqrtPriceX96 <= type(uint160).max
        uint256 scaledPriceX96 = uint256(sqrtPriceX96)
            .mul(10 ** decimalPrecision)
            .div(2 ** 96);
        uint256 scaledPriceBX96 = uint256(sqrtRatioBX96)
            .mul(10 ** decimalPrecision)
            .div(2 ** 96);

        uint256 decimalAdj = decimalPrecision.add(decimal1).sub(decimal0);
        uint256 preLiquidityRatioWithDecimals = scaledPriceX96
            .mul(scaledPriceBX96)
            .div(10 ** decimalAdj);

        liquidityRatioWithDecimals = preLiquidityRatioWithDecimals
            .mul(uint256(sqrtPriceX96).sub(sqrtRatioAX96))
            .div(uint256(sqrtRatioBX96).sub(sqrtPriceX96));
    }

    function verifyInputTokenIsLiquidityNftTokenPair(
        uint256 liquidityNftId,
        address inputToken,
        address nonfungiblePositionManagerAddress
    ) internal view {
        (
            address token0,
            address token1,
            ,
            ,
            ,
            ,

        ) = getLiquidityNftPositionsInfo(
                liquidityNftId,
                nonfungiblePositionManagerAddress
            );
        require(
            inputToken == token0 || inputToken == token1,
            "inputToken not in token pair"
        );
    }

    function verifyCurrentPriceInLiquidityNftRange(
        uint256 liquidityNftId,
        address uniswapV3FactoryAddress,
        address nonfungiblePositionManagerAddress
    ) internal view returns (bool isInRange, address liquidity0Token) {
        (, int24 tick, , , ) = getPoolInfoByLiquidityNft(
            liquidityNftId,
            uniswapV3FactoryAddress,
            nonfungiblePositionManagerAddress
        );
        (
            address token0,
            address token1,
            ,
            int24 tickLower,
            int24 tickUpper,
            ,

        ) = getLiquidityNftPositionsInfo(
                liquidityNftId,
                nonfungiblePositionManagerAddress
            );

        // tick out of range, tick <= tickLower left token0
        if (tick <= tickLower) {
            return (false, token0);

            // tick in range, tickLower < tick < tickUpper
        } else if (tick < tickUpper) {
            return (true, address(0));

            // tick out of range, tick >= tickUpper left token1
        } else {
            return (false, token1);
        }
    }

    function verifyCurrentPriceInLiquidityNftValidRange(
        int24 tickEndurance,
        int24 tickSpacing,
        uint256 liquidityNftId,
        address uniswapV3FactoryAddress,
        address nonfungiblePositionManagerAddress
    ) internal view returns (bool isInValidRange) {
        (, int24 tick, , , ) = getPoolInfoByLiquidityNft(
            liquidityNftId,
            uniswapV3FactoryAddress,
            nonfungiblePositionManagerAddress
        );
        (
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            ,

        ) = getLiquidityNftPositionsInfo(
                liquidityNftId,
                nonfungiblePositionManagerAddress
            );

        // tick out of valid range,
        // tick <= (tickLower + tickEndurance * tickSpacing)
        if (tick <= (tickLower + tickEndurance * tickSpacing)) {
            return false;

            // tick in valid range,
            // (tickLower + tickEndurance * tickSpacing) < tick < (tickUpper - tickEndurance * tickSpacing)
        } else if (tick < (tickUpper - tickEndurance * tickSpacing)) {
            return true;

            // tick out of valid range,
            // tick >= (tickUpper - tickEndurance * tickSpacing)
        } else {
            return false;
        }
    }

    function calculateTickBoundary(
        address poolAddress,
        int24 tickSpread,
        int24 tickSpacing
    ) internal view returns (int24 tickLower, int24 tickUpper) {
        // Get current tick
        (, , , int24 currentTick, , , ) = PoolHelper.getPoolInfo(poolAddress);

        // Calculate the floor tick value
        int24 tickFloor = floorTick(currentTick, tickSpacing);

        // Calculate the tickLower & tickToTickLower value
        tickLower = tickFloor - tickSpacing * tickSpread;
        int24 tickToTickLower = currentTick - tickLower;

        // Calculate the tickUpper & tickUpperToTick value
        tickUpper = floorTick((currentTick + tickToTickLower), tickSpacing);
        int24 tickUpperToTick = tickUpper - currentTick;

        // Check
        // if the tickSpacing is greater than 1
        // and
        // if the (tickToTickLower - tickUpperToTick) is greater than or equal to (tickSpacing / 2)
        if (
            tickSpacing > 1 &&
            (tickToTickLower - tickUpperToTick) >= (tickSpacing / 2)
        ) {
            // Increment the tickUpper by the tickSpacing
            tickUpper += tickSpacing;
        }
    }

    function floorTick(
        int24 tick,
        int24 tickSpacing
    ) internal pure returns (int24) {
        int24 baseFloor = tick / tickSpacing;

        if (tick < 0 && tick % tickSpacing != 0) {
            return (baseFloor - 1) * tickSpacing;
        }
        return baseFloor * tickSpacing;
    }
}

