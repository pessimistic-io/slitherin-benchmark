// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./TickMath.sol";
import "./SqrtPriceMath.sol";
import "./PositionKey.sol";
import "./LiquidityAmounts.sol";
import "./IUniswapV3Pool.sol";

/// @title Liquidity and ticks functions
/// @notice Provides functions for computing liquidity and ticks for token amounts and prices
library UniswapLiquidityManagement {
    /// @notice Get the liquidity amount of the given numbers of token0 and token1
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0 The amount of token0
    /// @param amount0 The amount of token1
    /// @return Amount of liquidity tokens
    function _liquidityForAmounts(address _pool, int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1)
        public
        view
        returns (uint128)
    {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(_pool).slot0();

        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount0,
            amount1
        );
    }

    /// @notice Get the amounts of the given numbers of liquidity tokens
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidity The amount of liquidity tokens
    /// @return Amount of token0 and token1
    function _amountsForLiquidity(address _pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        public
        view
        returns (uint256, uint256)
    {
        (uint160 sqrtRatioX96,,,,,,) = IUniswapV3Pool(_pool).slot0();
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }

    /// @notice Get the info of the given position
    /// @param _pool address of the pool to query
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @return liquidity The amount of liquidity of the position
    /// @return tokensOwed0 Amount of token0 owed (uncollected rewards)
    /// @return tokensOwed1 Amount of token1 owed (uncollected rewards)
    function _position(address _pool, int24 tickLower, int24 tickUpper)
        public
        view
        returns (uint128 liquidity, uint128 tokensOwed0, uint128 tokensOwed1)
    {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (liquidity,,, tokensOwed0, tokensOwed1) = IUniswapV3Pool(_pool).positions(positionKey);
    }

    /// @return tick Uniswap pool's current price tick
    function currentTick(address _pool) public view returns (int24 tick) {
        (, tick,,,,,) = IUniswapV3Pool(_pool).slot0();
    }
}

