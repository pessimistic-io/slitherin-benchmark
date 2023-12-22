// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./SafeMath.sol";
import "./IAaveOracle.sol";

import {SafeCast as SafeCastOZ } from "./libraries_SafeCast.sol";

import "./TickMath.sol";
import "./FullMath.sol";
import "./SqrtPriceMath.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./LiquidityAmounts.sol";

library HelperUtils {

    struct ComputeAmountParams {
        address tokenA;
        uint256 amountA;
        uint24 decimalsTokenA;
        uint24 decimalsTokenB;
        uint256 tokenBPrice;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
        int24 tick;
        address token0;
    }

    /**
     * @notice Computes the amount of tokenA needed to be swap for tokenB based on the current price.
     * 
     * @return The computed amount of tokenA to be exchanged for tokenB.
     * 
     * @dev Compute the amount of tokenB to be minted for the given amount of tokenA.
     * @dev Determines the proportion of tokenA to tokenB based on the calculated liquidity.
     * @dev Calls another function to calculate the amount of tokenA needed to be exchanged for tokenB based on the proportion.
     * @dev Ticks must be between the current tick of the pool.
     */
    function computeAmount(
        ComputeAmountParams memory params
    ) internal pure returns (uint256) {
        require(params.tick>params.tickLower && params.tick<params.tickUpper,"Helper: Current tick is not between tick upper and tick lower");

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

        uint256 amountB;
        if (params.token0 == params.tokenA) {
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
                params.sqrtPriceX96,
                sqrtRatioBX96,
                params.amountA
            );
            amountB = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(params.tickLower),
                params.sqrtPriceX96,
                liquidity,
                true
            );
        
        } else {
            uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
                sqrtRatioAX96,
                params.sqrtPriceX96,
                params.amountA
            );
            amountB = SqrtPriceMath.getAmount0Delta(
                params.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(params.tickUpper),
                liquidity,
                true
            );
        }

        return computeAmountAToSwap(params.amountA, params.decimalsTokenA, amountB, params.decimalsTokenB, params.tokenBPrice);
    }


    /**
     * @notice Computes the amount of tokenA needed to be swap for tokenB based on the given parameters.
     *
     * @param amountA The amount of tokenA to be considered for the swap.
     * @param decimalsTokenA The number of decimal of tokenA.
     * @param amountB The amount of tokenB required for the calculated proportion.
     * @param decimalsTokenB The number of decimal of tokenB.
     * @param tokenBPrice The current price of tokenB in terms of tokenA.
     * @return The computed amount of tokenA to be swap for tokenB.
     *
     * @dev Calculates the proportion of tokenA to tokenB based on the given amounts and decimal places.
     * @dev Adjusts the amounts to have the same decimal places for accurate division.
     * @dev Calculates the amount of tokenB to be minted based on the adjusted proportion and tokenB price.
     * @dev Converts the minted amount of tokenB to the equivalent amount of tokenA to swap.
     */
    function computeAmountAToSwap(
        uint256 amountA,
        uint24 decimalsTokenA,
        uint256 amountB,
        uint24 decimalsTokenB,
        uint256 tokenBPrice
    ) internal pure returns (uint256) {

        uint256 proportion; //proportion for each 1 tokenB
        if(decimalsTokenA>decimalsTokenB){

            uint256 amountBAdjusted = amountB*(10 ** (decimalsTokenA-decimalsTokenB));
            proportion = divide(amountA, amountBAdjusted, uint8(decimalsTokenA));
         
        } else {
            uint256 amountAAdjusted = amountA*10**(decimalsTokenB-decimalsTokenA);
            proportion = divide(amountAAdjusted,amountB,uint8(decimalsTokenA));

        }

        //formula for calculating amountB to mint -> amountA / (priceA + proportion)
        uint256 amountBToMintWithDecimal = divide(
            amountA,
            (tokenBPrice + proportion),
            SafeCastOZ.toUint8(uint256(decimalsTokenB))
        );

        //Convert amountB to amountA to swap
        return FullMath.mulDiv(amountBToMintWithDecimal,tokenBPrice,10**decimalsTokenB);
     
    }

    /**
     * @notice Divides two numbers and returns the result with the specified decimal places.
     *
     * @param numerator The numerator value to be divided.
     * @param denominator The denominator value to divide the numerator by.
     * @param decimals The number of decimal places for the result.
     * @return The division result with the specified decimal places.
     *
     * @dev Divides the numerator by the denominator and calculates the whole part.
     * @dev Calculates the decimal part by dividing the remainder of the numerator by the denominator.
     * @dev Returns the sum of the whole part and decimal part as the division result.
     */
    function divide(
        uint256 numerator,
        uint256 denominator,
        uint8 decimals
    ) internal pure returns (uint256) {
        uint256 wholePart = SafeMath.mul(
            SafeMath.div(numerator, denominator),
            10 ** decimals
        );
        uint256 decimalPart = SafeMath.div(
            SafeMath.mul(SafeMath.mod(numerator, denominator), 10 ** decimals),
            denominator
        );

        return SafeMath.add(wholePart, decimalPart);
    }

    /**
     * @notice Retrieves the price of a token in term of another token from an Aave oracle.
     *
     * @param token0 The address of the first token.
     * @param token0Decimals The number of decimal places for token0.
     * @param token1 The address of the second token.
     * @param token1Decimals The number of decimal places for token1.
     * @param priceToken0 A boolean indicating whether to return the price of token1 in terms of token0 (true) or vice versa (false).
     * @param oracle The Aave oracle contract used to fetch the asset prices.
     * @return The price of the tokens relative to each other based on the specified parameters.
     *
     * @dev Retrieves the USD price of token0 and token1 from the Aave oracle.
     * @dev Calculates the price based on the specified priceToken0 flag and the decimal places of the tokens.
     * @dev Returns the price of the tokens relative to each other.
     */
    function getTokenPrice(address token0, uint8 token0Decimals, address token1, uint8 token1Decimals, bool priceToken0, IAaveOracle oracle) internal view returns (uint256){
        uint256 priceToken0Usd = oracle.getAssetPrice(token0);
        uint256 priceToken1Usd = oracle.getAssetPrice(token1);
      
        uint256 price;
        if(priceToken0){
            price = FullMath.mulDiv(priceToken0Usd,10**token1Decimals,priceToken1Usd);
        } else {
             price = FullMath.mulDiv(priceToken1Usd,10**token0Decimals,priceToken0Usd);
        }

        return price;
    }

    /**
     * @notice Computes the minimum amount based on a given slippage percentage.
     *
     * @param amount The original amount.
     * @param slippage The slippage percentage represented as a value between 0 and 10,000 (inclusive).
     * @return The minimum amount calculated based on the specified slippage.
     *
     * @dev Calculates the minimum amount by subtracting the slippage amount from the original amount.
     * @dev The slippage is calculated as a fraction of the original amount based on the slippage percentage.
     * @dev Returns the minimum amount that accounts for the specified slippage.
     */
    function computeSlippage(uint256 amount, uint24 slippage) internal pure returns (uint256) {
        return SafeMath.sub(amount, FullMath.mulDiv(amount,slippage,10_000));
    }

    /**
     * @notice Retrieves information about a Uniswap V3 pool.
     *
     * @param tokenA The address of token A in the pool.
     * @param tokenB The address of token B in the pool.
     * @param poolFee The fee level of the pool.
     * @param uniswapFactory The Uniswap V3 factory contract used to fetch the pool.
     * 
     * @return sqrtPriceX96 The square root of the current price of the pool.
     * @return tick The current tick value of the pool.
     * @return token0 The address of the first token in the pool.
     * @return token1 The address of the second token in the pool.
     * @return fee The fee level of the pool.
     *
     */
    function getPoolInfo(address tokenA, address tokenB, uint24 poolFee, IUniswapV3Factory uniswapFactory ) internal view returns (uint160 sqrtPriceX96, int24 tick, address token0, address token1, uint24 fee){
        IUniswapV3Pool pool = IUniswapV3Pool(
            uniswapFactory.getPool(tokenA, tokenB, poolFee)
        );
        require(address(pool) != address(0), "Helper: Pool not found");

        ( sqrtPriceX96, tick, , , , , ) = pool.slot0();
        
        fee = poolFee;
        token0 = pool.token0();
        token1 = pool.token1();
    }

    /**
     * @notice Computes the minimum output amount based on the input amount, token price, pool fee, and slippage.
     *
     * @param amountIn The input amount.
     * @param tokenOutPrice The price of the output token.
     * @param tokenOutDecimals The number of decimal places for the output token.
     * @param poolFee The fee of the pool.
     * @param slippage The slippage percentage represented as a value between 0 and 10,000 (inclusive).
     * @return The minimum output amount calculated based on the specified parameters.
     *
     * @dev Computes the amount after subtracting the pool fee from the input amount.
     * @dev Calculates the expected output amount without considering slippage.
     * @dev Computes the minimum output amount by applying the slippage percentage to the expected output amount.
     * @dev Returns the minimum output amount that accounts for the specified pool fee and slippage.
     */
     // Compute amountMin =  ((amountIn - poolFee)/priceTokenOut) - slippage
    function computeAmountMin( uint256 amountIn, uint256 tokenOutPrice, uint8 tokenOutDecimals, uint24 poolFee, uint24 slippage ) internal pure returns (uint256) {

        //poolFee is in absolute term. We need tranform to basic points
        uint24 poolFeeBP = poolFee/100;
        uint256 amountInWithoutPoolFee = computeSlippage(amountIn, poolFeeBP);

        uint256 amountOutExpectedWithoutSlippage = divide(amountInWithoutPoolFee, tokenOutPrice, tokenOutDecimals);
        
        return computeSlippage(amountOutExpectedWithoutSlippage, slippage);

    }
}

