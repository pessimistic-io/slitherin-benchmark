//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./libraries_DataTypes.sol";

interface IOrderManagerEvents {
    // ====================================== Linked Order Events ======================================

    enum OrderType {
        TakeProfit,
        StopLoss
    }

    event LinkedOrderPlaced(
        bytes32 indexed orderHash,
        address indexed trader,
        PositionId indexed positionId,
        OrderType orderType,
        uint256 triggerCost,
        uint256 limitCost
    );

    event LinkedOrderCancelled(
        bytes32 indexed orderHash,
        address indexed trader,
        PositionId indexed positionId,
        OrderType orderType,
        uint256 triggerCost,
        uint256 limitCost
    );

    event LinkedOrderExecuted(
        bytes32 indexed orderHash,
        address indexed trader,
        PositionId indexed positionId,
        OrderType orderType,
        uint256 triggerCost,
        uint256 limitCost,
        uint256 keeperReward,
        uint256 lendingLiquidity,
        uint24 uniswapFee
    );

    // ====================================== Lever Order Events ======================================

    event LeverOrderPlaced(
        bytes32 indexed orderHash,
        address indexed trader,
        PositionId indexed positionId,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        bool recurrent
    );

    event LeverOrderCancelled(
        bytes32 indexed orderHash,
        address indexed trader,
        PositionId indexed positionId,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        bool recurrent
    );

    event LeverOrderExecuted(
        bytes32 indexed orderHash,
        address indexed trader,
        PositionId indexed positionId,
        uint256 keeperReward,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 actualLeverage,
        uint256 oraclePriceTolerance,
        uint256 lendingLiquidity,
        bool recurrent
    );

    // ====================================== Errors ======================================

    error NotPositionOwner();
    error PositionNotApproved();
    error OrderNotFound();
    error PnlNotReached(int256 actualPnl, int256 expectedPnl);
    error LeverageNotReached(uint256 currentLeverage, uint256 triggerLeverage);
    error TriggerCostNotReached(uint256 currentCost, uint256 triggerCost);
}

interface IOrderManager is IOrderManagerEvents {
    // ====================================== Linked Orders ======================================

    function placeLinkedOrder(PositionId positionId, OrderType orderType, uint256 triggerCost, uint256 limitCost)
        external;

    function executeLinkedOrder(
        PositionId positionId,
        OrderType orderType,
        uint256 triggerCost,
        uint256 limitCost,
        uint256 lendingLiquidity,
        uint24 uniswapFee
    ) external returns (uint256 keeperReward);

    function cancelLinkedOrder(PositionId positionId, OrderType orderType, uint256 triggerCost, uint256 limitCost)
        external;

    // ====================================== Lever Orders ======================================

    function placeLeverOrder(
        PositionId positionId,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        bool recurrent
    ) external;

    function executeLeverOrder(
        PositionId positionId,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        uint256 lendingLiquidity,
        bool recurrent
    ) external returns (uint256 keeperReward);

    function cancelLeverOrder(
        PositionId positionId,
        uint256 triggerLeverage,
        uint256 targetLeverage,
        uint256 oraclePriceTolerance,
        bool recurrent
    ) external;
}

