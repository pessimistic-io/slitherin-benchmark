// SPDX-License-Identifier: ISC
pragma solidity 0.7.5;
pragma abicoder v2;

import "./IRamsesV2Pool.sol";
import "./IRamsesV2Factory.sol";

interface IRamsesV2StateMulticall {
    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    struct TickBitMapMappings {
        int16 index;
        uint256 value;
    }

    struct TickInfo {
        uint128 liquidityGross;
        int128 liquidityNet;
        uint128 cleanUnusedSlot;
        int128 cleanUnusedSlot2;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
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
        uint160 secondsPerBoostedLiquidityPeriodX128;
        uint32 boostedInRange;
    }

    struct StateResult {
        IRamsesV2Pool pool;
        uint256 blockTimestamp;
        Slot0 slot0;
        uint128 liquidity;
        int24 tickSpacing;
        uint128 maxLiquidityPerTick;
        Observation observation;
        TickBitMapMappings[] tickBitmap;
        TickInfoMappings[] ticks;
    }

    function getFullState(
        IRamsesV2Factory factory,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (StateResult memory state);

    function getFullStateWithoutTicks(
        IRamsesV2Factory factory,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (StateResult memory state);

    function getFullStateWithRelativeBitmaps(
        IRamsesV2Factory factory,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int16 leftBitmapAmount,
        int16 rightBitmapAmount
    ) external view returns (StateResult memory state);

    function getAdditionalBitmapWithTicks(
        IRamsesV2Factory factory,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (TickBitMapMappings[] memory tickBitmap, TickInfoMappings[] memory ticks);

    function getAdditionalBitmapWithoutTicks(
        IRamsesV2Factory factory,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int16 tickBitmapStart,
        int16 tickBitmapEnd
    ) external view returns (TickBitMapMappings[] memory tickBitmap);
}

