// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.9;
pragma abicoder v2;

import "./Math.sol";
import "./IGrid.sol";
import "./IGridParameters.sol";
import "./IGridFactory.sol";
import "./GridAddress.sol";
import "./CallbackValidator.sol";
import "./BoundaryMath.sol";
import "./IMakerOrderManager.sol";
import "./IRelativeOrderManager.sol";
import "./Multicall.sol";
import "./AbstractPayments.sol";
import "./AbstractSelfPermit2612.sol";

/// @title The implementation for the maker order manager
contract MakerOrderManager is
    IMakerOrderManager,
    IRelativeOrderManager,
    AbstractPayments,
    AbstractSelfPermit2612,
    Multicall
{
    constructor(address _gridFactory, address _weth9) AbstractPayments(_gridFactory, _weth9) {}

    struct PlaceMakerOrderCalldata {
        GridAddress.GridKey gridKey;
        address payer;
    }

    /// @inheritdoc IGridPlaceMakerOrderCallback
    function gridexPlaceMakerOrderCallback(uint256 amount0, uint256 amount1, bytes calldata data) external override {
        PlaceMakerOrderCalldata memory decodeData = abi.decode(data, (PlaceMakerOrderCalldata));
        CallbackValidator.validate(gridFactory, decodeData.gridKey);

        if (amount0 > 0) pay(decodeData.gridKey.token0, decodeData.payer, _msgSender(), amount0);

        if (amount1 > 0) pay(decodeData.gridKey.token1, decodeData.payer, _msgSender(), amount1);
    }

    /// @inheritdoc IMakerOrderManager
    function initialize(InitializeParameters calldata parameters) external payable {
        GridAddress.GridKey memory gridKey = GridAddress.gridKey(
            parameters.tokenA,
            parameters.tokenB,
            parameters.resolution
        );
        address grid = GridAddress.computeAddress(gridFactory, gridKey);

        address recipient = parameters.recipient == address(0) ? _msgSender() : parameters.recipient;

        IGrid(grid).initialize(
            IGridParameters.InitializeParameters({
                priceX96: parameters.priceX96,
                recipient: recipient,
                orders0: parameters.orders0,
                orders1: parameters.orders1
            }),
            abi.encode(PlaceMakerOrderCalldata({gridKey: gridKey, payer: _msgSender()}))
        );
    }

    /// @inheritdoc IMakerOrderManager
    function createGridAndInitialize(InitializeParameters calldata parameters) external payable {
        address grid = IGridFactory(gridFactory).createGrid(
            parameters.tokenA,
            parameters.tokenB,
            parameters.resolution
        );

        address recipient = parameters.recipient == address(0) ? _msgSender() : parameters.recipient;

        IGrid(grid).initialize(
            IGridParameters.InitializeParameters({
                priceX96: parameters.priceX96,
                recipient: recipient,
                orders0: parameters.orders0,
                orders1: parameters.orders1
            }),
            abi.encode(
                PlaceMakerOrderCalldata({
                    gridKey: GridAddress.gridKey(parameters.tokenA, parameters.tokenB, parameters.resolution),
                    payer: _msgSender()
                })
            )
        );
    }

    /// @inheritdoc IMakerOrderManager
    function placeMakerOrder(
        PlaceOrderParameters calldata parameters
    ) external payable checkDeadline(parameters.deadline) returns (uint256 orderId) {
        GridAddress.GridKey memory gridKey = GridAddress.gridKey(
            parameters.tokenA,
            parameters.tokenB,
            parameters.resolution
        );
        address grid = GridAddress.computeAddress(gridFactory, gridKey);

        address recipient = parameters.recipient == address(0) ? _msgSender() : parameters.recipient;

        orderId = _placeMakerOrder(
            grid,
            gridKey,
            recipient,
            parameters.zero,
            parameters.boundaryLower,
            parameters.amount
        );
    }

    function _placeMakerOrder(
        address grid,
        GridAddress.GridKey memory gridKey,
        address recipient,
        bool zero,
        int24 boundaryLower,
        uint128 amount
    ) private returns (uint256 orderId) {
        orderId = IGrid(grid).placeMakerOrder(
            IGridParameters.PlaceOrderParameters({
                recipient: recipient,
                zero: zero,
                boundaryLower: boundaryLower,
                amount: amount
            }),
            abi.encode(PlaceMakerOrderCalldata({gridKey: gridKey, payer: _msgSender()}))
        );
    }

    /// @inheritdoc IMakerOrderManager
    function placeMakerOrderInBatch(
        PlaceOrderInBatchParameters calldata parameters
    ) external payable checkDeadline(parameters.deadline) returns (uint256[] memory orderIds) {
        GridAddress.GridKey memory gridKey = GridAddress.gridKey(
            parameters.tokenA,
            parameters.tokenB,
            parameters.resolution
        );
        address grid = GridAddress.computeAddress(gridFactory, gridKey);

        address recipient = parameters.recipient == address(0) ? _msgSender() : parameters.recipient;

        orderIds = IGrid(grid).placeMakerOrderInBatch(
            IGridParameters.PlaceOrderInBatchParameters({
                recipient: recipient,
                zero: parameters.zero,
                orders: parameters.orders
            }),
            abi.encode(PlaceMakerOrderCalldata({gridKey: gridKey, payer: _msgSender()}))
        );
    }

    /// @inheritdoc IRelativeOrderManager
    function placeRelativeOrder(
        RelativeOrderParameters calldata parameters
    ) external payable checkDeadline(parameters.deadline) returns (uint256 orderId) {
        // MOM_AIZ: amount is zero
        require(parameters.amount > 0, "MOM_AIZ");

        GridAddress.GridKey memory gridKey = GridAddress.gridKey(
            parameters.tokenA,
            parameters.tokenB,
            parameters.resolution
        );
        address grid = GridAddress.computeAddress(gridFactory, gridKey);

        (uint160 priceX96, , , ) = IGrid(grid).slot0();
        uint160 targetPriceX96 = parameters.priceDeltaX96 > 0
            ? priceX96 + uint160(parameters.priceDeltaX96)
            : priceX96 - uint160(-parameters.priceDeltaX96);

        // MOM_POR: price out of range
        require(BoundaryMath.isPriceX96InRange(targetPriceX96), "MOM_POR");
        require(
            targetPriceX96 >= parameters.priceMinimumX96 && targetPriceX96 <= parameters.priceMaximumX96,
            "MOM_POR"
        );

        int24 boundaryLower = BoundaryMath.rewriteToValidBoundaryLower(
            BoundaryMath.getBoundaryLowerAtBoundary(
                BoundaryMath.getBoundaryAtPriceX96(targetPriceX96),
                parameters.resolution
            ),
            parameters.resolution
        );

        // when the input is token1 and the price has reached the right boundary price,
        // we need to subtract a resolution from boundary lower
        if (!parameters.zero) {
            uint160 priceMaxX96 = BoundaryMath.getPriceX96AtBoundary(boundaryLower);
            boundaryLower = priceMaxX96 == targetPriceX96
                ? BoundaryMath.rewriteToValidBoundaryLower(
                    boundaryLower -= parameters.resolution,
                    parameters.resolution
                ) // avoid underflow
                : boundaryLower;
        }

        address recipient = parameters.recipient == address(0) ? _msgSender() : parameters.recipient;

        orderId = _placeMakerOrder(grid, gridKey, recipient, parameters.zero, boundaryLower, parameters.amount);
    }
}

