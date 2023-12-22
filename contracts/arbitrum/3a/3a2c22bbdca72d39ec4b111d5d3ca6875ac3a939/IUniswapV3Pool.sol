// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3Pool {
    function fee() external view returns (uint24);
    function liquidity() external view returns (uint128);
    function tickSpacing() external view returns (int24);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function protocolFees()
        external
        view
        returns (uint128 fee0, uint128 fee1);
    
    function tickBitmap(int16 wordPosition) external view returns (uint256);

    function ticks(
        int24 tick
    )
        external
        view
        returns (
            uint128 liquidityGross,
            // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
            int128 liquidityNet,
            // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
            // only has relative meaning, not absolute — the value depends on when the tick is initialized
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            // the cumulative tick value on the other side of the tick
            int56 tickCumulativeOutside,
            // the seconds per unit of liquidity on the _other_ side of this tick (relative to the current tick)
            // only has relative meaning, not absolute — the value depends on when the tick is initialized
            uint160 secondsPerLiquidityOutsideX128,
            // the seconds spent on the other side of the tick (relative to the current tick)
            // only has relative meaning, not absolute — the value depends on when the tick is initialized
            uint32 secondsOutside,
            // true iff the tick is initialized, i.e. the value is exactly equivalent to the expression liquidityGross != 0
            // these 8 bits are set to prevent fresh sstores when crossing newly initialized ticks
            bool initialized
        );

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

