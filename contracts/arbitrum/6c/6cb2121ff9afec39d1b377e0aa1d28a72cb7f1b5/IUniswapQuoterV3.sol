// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

/// @title UniswapQuoterV3 Interface
/// @notice Same as UniswapV3 QuoterV2 Interface, but always returns both estimated amountIn AND amountOut
/// @notice As well, has more verbose pass through reporting of Uniswap Errors (these are passed through instead of renaming as 'Unknown error')
/// @notice Supports quoting the calculated amounts from exact input or exact output swaps.
/// @notice For each pool also tells you the number of initialized ticks crossed and the sqrt price of the pool after the swap.
/// @dev These functions are not marked view because they rely on calling non-view functions and reverting
/// to compute the result. They are also not gas efficient and should not be called on-chain.
interface IUniswapQuoterV3 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountIn The desired input amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// @return amountInQuote The amount of input Token used for the swap  given params (could be less than specified amount given dex liquidity or price limit)
    /// @return amountOutQuote The amount of `tokenOut` that would be received from the swap given params
    /// @return sqrtPriceX96After The sqrt price of the pool after the swap
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (
            uint256 amountInQuote,
            uint256 amountOutQuote,
            uint160 sqrtPriceX96After,
            uint256 gasEstimate
        );

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the amount in required to receive the given exact output amount but for a swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactOutputSingleParams`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountOut The desired output amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// @return amountInQuote The amount required as the input for the swap in order to receive `amountOut` or reach price limit
    /// @return amountOutQuote The amount expected at output from the swap given params (could be less than specified amount given dex liquidity or price limit)
    /// @return sqrtPriceX96After The sqrt price of the pool after the swap
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        returns (
            uint256 amountInQuote,
            uint256 amountOutQuote,
            uint160 sqrtPriceX96After,
            uint256 gasEstimate
        );
}

