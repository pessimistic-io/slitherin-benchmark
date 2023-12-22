// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IAlgebraPool} from "./IAlgebraPool.sol";
import {IAlgebraFactory} from "./IAlgebraFactory.sol";
import {IERC20Minimal} from "./IERC20Minimal.sol";

contract AlgebraStateMulticall {
    struct Slot0 {
        uint160 sqrtPriceX96;
        uint16 fee;
        int24 tick;
        uint16 observationIndex;
        uint8 communityFeeToken0;
        uint8 communityFeeToken1;
        bool unlocked;
    }

    struct TickBitMapMappings {
        int16 index;
        uint256 value;
    }

    struct TickInfo {
        uint128 liquidityGross;
        int128 liquidityNet;
        int56 tickCumulativeOutside;
        uint160 secondsPerLiquidityOutsideX128;
        uint32 secondsOutside;
        bool initialized;
    }

    struct TickInfoMappings {
        int24 index;
        TickInfo value;
    }

    struct Observation {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
    }

    struct StateResult {
        IAlgebraPool pool;
        uint256 blockTimestamp;
        Slot0 slot0;
        uint128 liquidity;
        int24 tickSpacing;
        uint128 maxLiquidityPerTick;
        uint256 balance0;
        uint256 balance1;
        Observation observation;
        TickBitMapMappings[] tickBitmap;
        TickInfoMappings[] ticks;
    }

    function getFullStateWithRelativeBitmaps(
        IAlgebraFactory factory,
        address tokenIn,
        address tokenOut,
        int16 leftBitmapAmount,
        int16 rightBitmapAmount
    ) external view returns (StateResult memory state) {
        require(leftBitmapAmount > 0, "leftBitmapAmount <= 0");
        require(rightBitmapAmount > 0, "rightBitmapAmount <= 0");

        state = _fillStateWithoutBitmapsAndTicks(
            factory,
            tokenIn,
            tokenOut
        );
        int16 currentBitmapIndex = _getBitmapIndexFromTick(
            state.slot0.tick / state.tickSpacing
        );

        state.tickBitmap = _calcTickBitmaps(
            factory,
            tokenIn,
            tokenOut,
            currentBitmapIndex - leftBitmapAmount,
            currentBitmapIndex + rightBitmapAmount
        );
    }

    function _fillStateWithoutBitmapsAndTicks(
        IAlgebraFactory factory,
        address tokenIn,
        address tokenOut
    ) internal view returns (StateResult memory state) {
        IAlgebraPool pool = _getPool(factory, tokenIn, tokenOut);

        state.pool = pool;
        state.blockTimestamp = block.timestamp;
        state.liquidity = pool.liquidity();
        state.tickSpacing = pool.tickSpacing();
        state.maxLiquidityPerTick = pool.maxLiquidityPerTick();
        state.balance0 = _getBalance(pool.token0(), address(pool));
        state.balance1= _getBalance(pool.token1(), address(pool));

        (
            state.slot0.sqrtPriceX96,
            state.slot0.tick,
            state.slot0.fee,
            state.slot0.observationIndex,
            state.slot0.communityFeeToken0,
            state.slot0.communityFeeToken1,
            state.slot0.unlocked
        ) = pool.globalState();

        (
            state.observation.initialized,
            state.observation.blockTimestamp,
            state.observation.tickCumulative,
            state.observation.secondsPerLiquidityCumulativeX128,
            ,
            ,
        ) = pool.timepoints(state.slot0.observationIndex);
    }

    function _calcTickBitmaps(
        IAlgebraFactory factory,
        address tokenIn,
        address tokenOut,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) internal view returns (TickBitMapMappings[] memory tickBitmap) {
        IAlgebraPool pool = _getPool(factory, tokenIn, tokenOut);
        uint256 numberOfPopulatedBitmaps = 0;
        for (int256 i = tickBitmapStart; i <= tickBitmapEnd; i++) {
            uint256 bitmap = pool.tickTable(int16(i));
            if (bitmap == 0) continue;
            numberOfPopulatedBitmaps++;
        }

        tickBitmap = new TickBitMapMappings[](numberOfPopulatedBitmaps);
        uint256 globalIndex = 0;
        for (int256 i = tickBitmapStart; i <= tickBitmapEnd; i++) {
            int16 index = int16(i);
            uint256 bitmap = pool.tickTable(index);
            if (bitmap == 0) continue;

            tickBitmap[globalIndex] = TickBitMapMappings({
                index: index,
                value: bitmap
            });
            globalIndex++;
        }
    }

    function _getPool(
        IAlgebraFactory factory,
        address tokenIn,
        address tokenOut
    ) internal view returns (IAlgebraPool pool) {
        pool = IAlgebraPool(factory.poolByPair(tokenIn, tokenOut));
        require(address(pool) != address(0), "Pool does not exist");
    }

    function _getBitmapIndexFromTick(int24 tick) internal pure returns (int16) {
        return int16(tick >> 8);
    }

    function _getBalance(address token, address pool) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, pool)
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }
}

