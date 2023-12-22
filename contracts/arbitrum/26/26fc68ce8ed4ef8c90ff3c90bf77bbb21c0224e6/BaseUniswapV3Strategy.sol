// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./UniswapV3Library.sol";
import "./BaseConcentratedLiquidityStrategy.sol";

abstract contract BaseUniswapV3Strategy is BaseConcentratedLiquidityStrategy {
    using SafeERC20 for IERC20;
    using UniswapV3Library for UniswapV3Library.Data;

    UniswapV3Library.Data public uniswap;

    constructor(IUniswapV3Pool pool, INonfungiblePositionManager positionManager) {
        uniswap = UniswapV3Library.Data({
            token0: pool.token0(),
            token1: pool.token1(),
            fee: pool.fee(),
            positionManager: positionManager,
            pool: pool,
            positionTokenId: 0,
            tickSpacing: pool.tickSpacing()
        });

        uniswap.performApprovals();
    }

    function _processAdditionalRewards() internal virtual override {}

    function token0() public view override returns (address) {
        return uniswap.token0;
    }

    function token1() public view override returns (address) {
        return uniswap.token1;
    }

    function _isPositionExists() internal view override returns (bool) {
        return !(uniswap.positionTokenId == 0);
    }

    function _tickSpacing() internal view override returns (int24) {
        return uniswap.tickSpacing;
    }

    function _increaseLiquidity(uint256 amount0, uint256 amount1) internal override {
        uniswap.increaseLiquidity(amount0, amount1);
    }

    function _decreaseLiquidity(uint128 liquidity) internal override returns (uint256 amount0, uint256 amount1) {
        return uniswap.decreaseLiquidity(liquidity);
    }

    function _mint(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1) internal override {
        uniswap.mint(tickLower, tickUpper, amount0, amount1);
    }

    function getPoolData() public view override returns (int24 currentTick, uint160 sqrtPriceX96) {
        return uniswap.getPoolData();
    }

    function getPositionData() public view override returns (PositionData memory) {
        return uniswap.getPositionData();
    }

    function _collectAllAndBurn() internal override {
        uniswap.collect(type(uint128).max, type(uint128).max);
        uniswap.burn();
    }

    function _collect() internal override {
        uniswap.collect(type(uint128).max, type(uint128).max);
    }
}

