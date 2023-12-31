// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

/// @title Order Book Helper Interface
/// @notice Helper contracts provides view functions for Lighter users
/// to fetch and compute swap and book information
interface IOrderBookHelper {
    /// @notice approveRouter approves the router to spend the given token, only owner can call
    /// @param token The token to approve
    function approveRouter(address token) external;

    /// @notice Returns the details for all existing order books
    /// @return orderBookIds The id of the order book
    /// @return orderBookAddresses The address of the order book
    /// @return token0s The base token of the order book
    /// @return token1s The quote token of the order book
    /// @return sizeTicks The size tick of the order book
    /// @return priceTicks The price tick of the order book
    function getAllOrderBooks()
        external
        view
        returns (
            uint8[] memory orderBookIds,
            address[] memory orderBookAddresses,
            address[] memory token0s,
            address[] memory token1s,
            uint128[] memory sizeTicks,
            uint128[] memory priceTicks
        );

    /// @notice Returns max amount to receive for given input amount
    /// @param orderBookId Id of the order book to get the swap data on
    /// @param isAsk True if the amountIn is token0, false otherwise
    /// @param amountIn Upper bound for the amount to send for the swap.
    /// @return resAmountIn The amount of in token
    /// @return amountOut The amount of out token
    function quoteExactInput(
        uint8 orderBookId,
        bool isAsk,
        uint256 amountIn
    ) external view returns (uint256 resAmountIn, uint256 amountOut);

    /// @notice Swaps given amount of tokens for the given order book and min amount to receive
    /// Returned amount is the swapped amount bounded by receiving at least amountOutMin tokens
    /// @param orderBookId Id of the order book to get the swap data on
    /// @param isAsk True if the amountIn is token0, false otherwise
    /// @param amountIn amount to send for the swap.
    /// @param minAmountOut Lower bound for the amount to receive after the swap.
    /// @return amountOut The amount of out token received
    function swapExactInput(
        uint8 orderBookId,
        bool isAsk,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);
}

