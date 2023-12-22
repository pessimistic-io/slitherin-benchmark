// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./TickMath.sol";
import "./SqrtPriceMath.sol";
import "./PositionKey.sol";
import "./LiquidityAmounts.sol";
import "./IUniswapV3Pool.sol";
import "./Math.sol";

import {Range} from "./EnigmaStructs.sol";

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

    /// @dev Calculates the largest possible `amount0` and `amount1` such that
    /// they're in the same proportion as total amounts, but not greater than
    /// `amount0Desired` and `amount1Desired` respectively.
    function calcSharesAndAmounts(
        uint256 _totalSupply,
        uint256 totalAmount0,
        uint256 totalAmount1,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public pure returns (uint256 shares, uint256 amount0, uint256 amount1) {
        uint256 totalSupply = _totalSupply;

        //add currently active tokens supplied as liquidity
        uint256 total0 = totalAmount0;
        uint256 total1 = totalAmount1;
        //LiquidityAmounts.getAmountsOf(address(strategy), strategy.strategyActiveBins(), address(strategy.lbPair()));

        // If totalSupply > 0, vault can't be empty
        assert(totalSupply == 0 || total0 > 0 || total1 > 0);

        if (totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            shares = Math.max(amount0, amount1);
        } else if (total0 == 0) {
            amount1 = amount1Desired;
            shares = (amount1 * totalSupply) / total1;
        } else if (total1 == 0) {
            amount0 = amount0Desired;
            shares = (amount0 * totalSupply) / total0;
        } else {
            uint256 cross = Math.min((amount0Desired * total1), (amount1Desired * total0));

            require(cross > 0, "cross");

            // Round up amounts
            amount0 = (cross - 1) / total1 + 1;
            amount1 = (cross - 1) / total0 + 1;
            shares = (cross * totalSupply) / total0 / total1;
        }
    }

    function rangeExists(Range[] memory currentRanges_, Range memory range_)
        public
        pure
        returns (bool ok, uint256 index)
    {
        for (uint256 i; i < currentRanges_.length; i++) {
            ok = range_.tickLower == currentRanges_[i].tickLower && range_.tickUpper == currentRanges_[i].tickUpper
                && range_.feeTier == currentRanges_[i].feeTier;
            if (ok) {
                index = i;
                break;
            }
        }
    }
}

