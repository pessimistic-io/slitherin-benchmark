// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./console.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ILiquidityPool.sol";
import "./ISwapRouter.sol";
import "./IQuoterV2.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";

contract UniswapV3LiquidityPool is ILiquidityPool {
    using SafeERC20 for IERC20;

    uint24 public immutable fee;

    IUniswapV3Pool public immutable pool;
    ISwapRouter public immutable router;
    IQuoterV2 public immutable quoter;

    constructor(address pool_,
                address router_,
                address quoter_) {
        pool = IUniswapV3Pool(pool_);
        router = ISwapRouter(router_);
        quoter = IQuoterV2(quoter_);

        token0 = pool.token0();
        token1 = pool.token1();
        fee = pool.fee();
    }

    function previewSwap(address tokenIn, uint128 amountIn, uint128 sqrtPriceLimitX96)
        external override returns (uint256, uint256) {

        require(address(pool) != address(0), "ULP: no pool");

        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenIn == token0 ? token1 : token0,
            amountIn: amountIn,
            fee: fee,
            sqrtPriceLimitX96: sqrtPriceLimitX96 });

        console.log("Call preview swap with", tokenIn, amountIn);

        (uint256 amountOut, uint160 sqrtPriceX96After, ,) = quoter.quoteExactInputSingle(params);

        console.log("Call preview swap got", amountOut);

        return (amountOut, uint256(sqrtPriceX96After));
    }

    function previewSwapOut(address tokenIn, uint128 amountOut, uint128 sqrtPriceLimitX96)
        external override returns (uint256, uint256) {
        IQuoterV2.QuoteExactOutputSingleParams memory params = IQuoterV2.QuoteExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenIn == token0 ? token1 : token0,
            amount: amountOut,
            fee: fee,
            sqrtPriceLimitX96: sqrtPriceLimitX96 });

        (uint256 amountIn, uint160 sqrtPriceX96After, ,) = quoter.quoteExactOutputSingle(params);
        return (amountIn, uint256(sqrtPriceX96After));
    }

    function swap(address recipient,
                  address tokenIn,
                  uint128 amountIn,
                  uint128 amountOutMinimum,
                  uint128 sqrtPriceLimitX96)
        external override returns (uint256) {

        require(address(pool) != address(0), "ULP: no pool");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        assert(IERC20(tokenIn).balanceOf(address(this)) >= amountIn);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenIn == token0 ? token1 : token0,
                fee: fee,
                recipient: recipient,
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: sqrtPriceLimitX96 });

        uint256 amountOut = router.exactInputSingle(params);
        return amountOut;
    }
}

