// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IRouteQuoterParameters.sol";

/// @title IUniswapRouteQuoter Interface
/// @notice Supports the ability to quote the calculated amounts from exact input or exact output swaps
/// @notice For each pool also tells you the number of initialized ticks crossed and the sqrt price of the pool after the swap.
/// @dev These functions are not marked view because they rely on calling non-view functions and reverting
/// to compute the result. They are also not gas efficient and should not be called on-chain.
interface IUniswapRouteQuoter is IRouteQuoterParameters {
    /// @notice Returns the amount out received for a given exact input but for a swap of a single pool
    /// @param parameters The parameters for the quote, encoded as `QuoteExactInputSingleParameters`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountIn The desired input amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// @return result The result of the quote, encoded as `QuoteExactResult`
    function v3QuoteExactInputSingle(
        QuoteExactInputSingleParameters memory parameters
    ) external returns (QuoteExactResult memory result);

    /// @notice Returns the amount in required to receive the given exact output amount but for a swap of a single pool
    /// @param parameters The parameters for the quote, encoded as `QuoteExactOutputSingleParameters`
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// fee The fee of the token pool to consider for the pair
    /// amountOut The desired output amount
    /// sqrtPriceLimitX96 The price limit of the pool that cannot be exceeded by the swap
    /// @return result The result of the quote, encoded as `QuoteExactResult`
    function v3QuoteExactOutputSingle(
        QuoteExactOutputSingleParameters memory parameters
    ) external returns (QuoteExactResult memory result);

    struct V2GetPairAmountInParameters {
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
    }

    /// @notice Returns the amount out received for a given exact output but for a swap of a single V2 pool
    /// @param parameters The parameters for the quote, encoded as `V2GetPairAmountInParameters`
    /// amountOut The desired output amount
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// amountIn The amount of `tokenIn` that would be required
    function v2GetPairAmountIn(V2GetPairAmountInParameters memory parameters) external view returns (uint256);

    struct V2GetPairAmountOutParameters {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
    }

    /// @notice Returns the amount out received for a given exact input but for a swap of a single V2 pool
    /// @param parameters The parameters for the quote, encoded as `V2GetPairAmountOutParameters`
    /// amountIn The desired input amount
    /// tokenIn The token being swapped in
    /// tokenOut The token being swapped out
    /// @return amountOut The amount of `tokenOut` that would be received
    function v2GetPairAmountOut(V2GetPairAmountOutParameters memory parameters) external view returns (uint256);
}

