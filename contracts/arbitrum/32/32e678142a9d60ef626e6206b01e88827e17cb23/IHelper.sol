// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/**
 * @title The interface for a Helper
 * @notice This Helper facilitates the administration of DAO treasury
 */
interface IHelper {
    /**
     * @notice Emitted when liquidity is increased for a position NFT
     * @dev Also emitted when a token is minted
     * @param tokenId The ID of the token for which liquidity was minted
     * @param liquidity The amount by which liquidity for the NFT position was minted
     * @param amount0 The amount of token0 that was paid for the increase in liquidity
     * @param amount1 The amount of token1 that was paid for the increase in liquidity
     */
    event MintUniswapPosition(
        address sender,
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @notice Emitted by the pool for any swaps between token0 and token1
     * @param sender The address that initiated the swap call, and that received the callback
     * @param tokenIn Token from swap
     * @param amount0 The delta of the token0 balance of the pool
     * @param tokenOut Token to swap
     * @param amount1 The delta of the token1 balance of the pool
     * @param price of tokenOut in terms of tokenIn
     */
    event SwapUniswap(
        address indexed sender,
        address tokenIn,
        uint256 amount0,
        address tokenOut,
        uint256 amount1,
        uint256 price
    );

    /**
     * Used to avoid stack to deep within function
     */
    struct MintPositionInternalParams {
        address token0;
        uint256 amount0;
        address token1;
        uint256 amount1;
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 poolFee;
        uint8 tokenADecimals;
        uint8 tokenBDecimals;
        uint256 tokenBPrice;
    }

    /**
     * @notice Mints a liquidity position in Uniswap by providing an amount of tokenA.
     * The function performs calculations to determine the proportion of tokenA and tokenB
     * to be minted in the position based on the specified ticks.
     * Once the proportion is determined, it calculates the required amount of tokenB to be swaped
     * and performs the swap. After that, it mints the liquidity position in Uniswap.
     * Any remaining tokens are returned to the `msg.sender`.
     * 
     * @param tokenA The address of tokenA.
     * @param amountA The amount of tokenA to be provided.
     * @param tokenB The address of tokenB.
     * @param poolFee The pool fee to be applied in the Uniswap pool.
     * @param tickLower The lower tick of the position range.
     * @param tickUpper The upper tick of the position range.
     * @param slippage The maximum allowed slippage for the swap.
     *
     * @dev msg.sender must have been previously approved as spender to the contract amountA
     */
    function mintPosition(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint24 poolFee,
        int24 tickLower,
        int24 tickUpper,
        uint24 slippage
    ) external;

    /**
     * @notice Allows swapping one token for another with custom slippage and pool fee.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens to be swapped.
     * @param tokenOut The address of the output token.
     * @param slippage The maximum allowed slippage for the swap.
     * @param poolFee The pool fee to be applied in the swap.
     *
     * @dev The minimum output amount for swap will be calculated based on the slippage specified
     *      and the price obtained from an oracle at the time of executing the instruction.
     */
    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint24 slippage,
        uint24 poolFee
    ) external;
}

