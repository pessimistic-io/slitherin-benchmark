// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title The interface for the relative order manager
interface IRelativeOrderManager {
    struct RelativeOrderParameters {
        uint256 deadline;
        address recipient;
        address tokenA;
        address tokenB;
        int24 resolution;
        bool zero;
        uint128 amount;
        /// @dev The price delta is the price difference between the order price and the grid price, as a Q64.96.
        /// Positive values mean the order price is higher than the grid price, and negative values mean the order price is
        /// lower than the grid price.
        int160 priceDeltaX96;
        /// @dev The minimum price of the order, as a Q64.96.
        uint160 priceMinimumX96;
        /// @dev The maximum price of the order, as a Q64.96.
        uint160 priceMaximumX96;
    }

    /// @notice Places a relative order
    /// @param parameters The parameters for the relative order
    /// @return orderId The unique identifier of the order
    function placeRelativeOrder(RelativeOrderParameters calldata parameters) external payable returns (uint256 orderId);
}

