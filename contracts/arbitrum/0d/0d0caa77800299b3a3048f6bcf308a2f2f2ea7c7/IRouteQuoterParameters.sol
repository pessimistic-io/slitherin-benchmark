// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IRouteQuoterParameters {
    struct QuoteExactInputSingleParameters {
        /// @dev The token being swapped in
        address tokenIn;
        /// @dev The token being swapped out
        address tokenOut;
        /// @dev The desired input amount
        uint256 amountIn;
        /// @dev The resolution of the token grid to consider for the pair
        int24 resolution;
        /// @dev The price limit of the grid that cannot be exceeded by the swap, be same as sqrtPriceLimitX96
        /// in UniswapV3, priceLimitX96 in Gridex
        uint160 priceLimit;
    }

    struct QuoteExactOutputSingleParameters {
        /// @dev The token being swapped in
        address tokenIn;
        /// @dev The token being swapped out
        address tokenOut;
        /// @dev The desired output amount
        uint256 amountOut;
        /// @dev The resolution of the token grid to consider for the pair
        int24 resolution;
        /// @dev The price limit of the grid that cannot be exceeded by the swap, be same as sqrtPriceLimitX96
        /// in UniswapV3, priceLimitX96 in Gridex
        uint160 priceLimit;
    }

    struct QuoteExactResult {
        /// @dev The amount required as the input of the swap in order to receive `amountOut`
        uint256 amountToPay;
        /// @dev The amount to receive of the swap
        uint256 amountOut;
        /// @dev The price of the grid after the swap, be same as sqrtPriceLimitX96 in UniswapV3,
        /// priceLimitX96 in Gridex
        uint160 priceAfter;
        /// @dev The number of initialized boundaries that the swap crossed
        uint32 initializedBoundariesCrossed;
        /// @dev That the swap may consume
        uint256 gasEstimate;
    }
}

