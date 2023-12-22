//SPDX-License-Identifier: Unlicense
pragma solidity =0.7.6;
pragma abicoder v2;

import "./ERC20.sol";
import "./SafeCast.sol";
import "./TickMath.sol";
import "./IUniswapV3Pool.sol";
import "./PositionKey.sol";
import "./LiquidityAmounts.sol";

library PoolActions {

    using SafeCast for uint256;

    struct MintCallbackData {
        address payer;
    }

    struct SwapCallbackData {
        bool zeroForOne;
    }

    // Mint liquidity that will be owned by the contract. Assumes correct ratio! (As calculated in swapToRatio)
    // Assumes amount0Desired = amount1Desired for the range between tickLower and tickUpper at the current tick.
    // @param amount0Desired token0 amount that will go into liquidity.
    // @param amount0Desired token1 amount that will go into liquidity.
    function mintManagedLiquidity(IUniswapV3Pool pool, uint256 amount0Desired, uint256 amount1Desired, int24 tickLower, int24 tickUpper) public returns (uint128 liquidity) {
        if(amount0Desired == 0 && amount1Desired == 0) return 0;

        // compute the liquidity amount. There'll be small amounts left over as the pool is always changing.
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, 
            TickMath.getSqrtRatioAtTick(tickLower), 
            TickMath.getSqrtRatioAtTick(tickUpper), 
            amount0Desired, 
            amount1Desired
        );

        if(liquidity > 0)
            pool.mint(address(this), tickLower, tickUpper, liquidity,  abi.encode(MintCallbackData({payer: address(this)})));
    }

    // Burn liquidity mangaged by the contract. Assumes the harvest() method was called first so rewards/fees are properly calculated.
    function burnManagedLiquidity(IUniswapV3Pool pool, uint128 amount, int24 tickLower, int24 tickUpper) public returns (uint256 amount0, uint256 amount1) {
        require(amount > 0,"I");

        (uint256 float0, uint256 float1) = pool.burn(tickLower, tickUpper, amount);

        (amount0, amount1) = pool.collect(address(this), tickLower, tickUpper, float0.toUint128(), float1.toUint128());
    }

    function harvest(IUniswapV3Pool pool, int24 tickLower, int24 tickUpper) public returns (uint256 rewards0, uint256 rewards1, uint256 fees0, uint256 fees1) {
        if(getPosition(pool, tickLower, tickUpper) == 0) return (rewards0, rewards1, fees0, fees1);
        // 0 burn "poke" to tell pool to recalculate rewards
        pool.burn(tickLower, tickUpper, 0);

        (rewards0, rewards1) = pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);

        // remove fee of 10%
        fees0 = rewards0 * 10 / 100;
        fees1 = rewards1 * 10 / 100;

        if(fees0 > 0) rewards0 -= fees0;
        if(fees1 > 0) rewards1 -= fees1;
    }

    function calculateRefund(IUniswapV3Pool pool, uint128 liquidity, uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper) public view returns (uint256 leftover0, uint256 leftover1) {
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        (uint256 used0, uint256 used1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, 
            TickMath.getSqrtRatioAtTick(tickLower), 
            TickMath.getSqrtRatioAtTick(tickUpper), 
            liquidity);

        leftover0 = amount0 - used0;
        leftover1 = amount1 - used1;

        uint256 t0 = IERC20(pool.token0()).balanceOf(address(this));
        uint256 t1 = IERC20(pool.token1()).balanceOf(address(this));

        // if we don't have the leftover amount (likely due to rounding errors), pay as much as we can
        leftover0 = leftover0 > t0 ? t0 : leftover0;
        leftover1 = leftover1 > t1 ? t1 : leftover1;
    }

    function swapWithLimit(IUniswapV3Pool pool, address _tokenIn, address _tokenOut, uint256 _amountIn, uint160 _slippageBps) public returns (uint256 amountOut, uint256 leftover) {
        bool zeroForOne = _tokenIn < _tokenOut;
        SwapCallbackData memory data = SwapCallbackData({zeroForOne: zeroForOne});

        (uint160 price,,,,,,) = pool.slot0();
        uint160 priceImpact = price * _slippageBps / 1e5;
        uint160 sqrtPriceLimitX96 = zeroForOne ? price - priceImpact : price + priceImpact;

        (int256 amount0, int256 amount1) =
            pool.swap(
                address(this),
                zeroForOne,
                _amountIn.toInt256(),
                sqrtPriceLimitX96,
                abi.encode(data)
            );

        amountOut = uint256(-(zeroForOne ? amount1 : amount0));

        // If we have excess _amountIn, that means there's too much slippage for the pool size. Lock deposits. Unlock them if we're below this level.
        leftover = zeroForOne ? _amountIn - uint256(amount0) : _amountIn - uint256(amount1);
    }

    function getPosition(IUniswapV3Pool pool, int24 tickLower, int24 tickUpper) public view returns (uint128 liquidity) {
        (liquidity, , , , ) = pool.positions(PositionKey.compute(address(this), tickLower, tickUpper));
        return liquidity;
    }

    // given amount0 and amount1, how much is useable RIGHT NOW as liquidity? We need this to calculate leftovers for swapping.
    function getUsableLiquidity(IUniswapV3Pool pool, uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper) public view returns (uint256, uint256) {
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint128 liquidityAmounts = LiquidityAmounts.getLiquidityForAmounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
        return LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidityAmounts);
    }

    // normalize on a scale of 0 - 100
    function normalizeRange(IUniswapV3Pool pool, int24 min, int24 max) public view returns (uint256) {
        (,int24 tick,,,,,) = pool.slot0();
        require(tick >= min && tick <= max && max > min,"II");
        return uint256((tick - min) * 100 / (max - min));
    }
}
