// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IGridPlaceMakerOrderCallback.sol";
import "./IGridParameters.sol";

/// @title The interface for the maker order manager
interface IMakerOrderManager is IGridPlaceMakerOrderCallback {
    struct InitializeParameters {
        address tokenA;
        address tokenB;
        int24 resolution;
        uint160 priceX96;
        address recipient;
        IGridParameters.BoundaryLowerWithAmountParameters[] orders0;
        IGridParameters.BoundaryLowerWithAmountParameters[] orders1;
    }

    struct PlaceOrderParameters {
        uint256 deadline;
        address recipient;
        address tokenA;
        address tokenB;
        int24 resolution;
        bool zero;
        int24 boundaryLower;
        uint128 amount;
    }

    struct PlaceOrderInBatchParameters {
        uint256 deadline;
        address recipient;
        address tokenA;
        address tokenB;
        int24 resolution;
        bool zero;
        IGridParameters.BoundaryLowerWithAmountParameters[] orders;
    }

    /// @notice Initializes the grid with the given parameters
    function initialize(InitializeParameters calldata initializeParameters) external payable;

    /// @notice Places a maker order on the grid
    /// @return orderId The unique identifier of the order
    function placeMakerOrder(PlaceOrderParameters calldata parameters) external payable returns (uint256 orderId);

    function settleMakerOrderAndCollectInBatch(
        address grid,
        address recipient,
        uint256[] memory orderIds,
        bool unwrapWETH9
    ) external   returns (uint128 amount0Total, uint128 amount1Total);

}

