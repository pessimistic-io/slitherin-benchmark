// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.6;

pragma abicoder v2;

import "./IUniswapV3Pool.sol";

interface IUniswapHelper {

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external view returns (int24 tick);
    function getSqrtRatioAtTick(int24 tick) external pure returns (uint160 sqrtPriceX96);
    function getSpotPrice(IUniswapV3Pool pool, bool isVolTokenToken0) external view returns (uint256 price);
    function getTWAPPriceDelta(IUniswapV3Pool pool, uint32 interval) external view returns (uint256 priceChange, uint256 fromPrice);

    function getLiquidityForAmount0(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount0) external pure returns (uint128 liquidity);
    function getLiquidityForAmount1(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount1) external pure returns (uint128 liquidity);
    function getAmount0ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity) external pure returns (uint256 amount0);
    function getAmount1ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity) external pure returns (uint256 amount1);
    function uint256ToX96(uint256 number) external pure returns (uint160 result);

    function PRECISION_DECIMALS() external view returns (uint256);
}

