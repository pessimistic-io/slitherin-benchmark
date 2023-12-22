// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "./IGMXOrder.sol";

library OrderUtils {

    error InvalidOrderType();

    // @dev CreateOrderParams struct used in createOrder to avoid stack
    // too deep errors
    //
    // @param addresses address values
    // @param numbers number values
    // @param orderType for order.orderType
    // @param decreasePositionSwapType for order.decreasePositionSwapType
    // @param isLong for order.isLong
    // @param shouldUnwrapNativeToken for order.shouldUnwrapNativeToken
    struct CreateOrderParams {
        CreateOrderParamsAddresses addresses;
        CreateOrderParamsNumbers numbers;
        IGMXOrder.OrderType orderType;
        IGMXOrder.DecreasePositionSwapType decreasePositionSwapType;
        bool isLong;
        bool shouldUnwrapNativeToken;
        bytes32 referralCode;
    }

    // @param receiver for order.receiver
    // @param callbackContract for order.callbackContract
    // @param market for order.market
    // @param initialCollateralToken for order.initialCollateralToken
    // @param swapPath for order.swapPath
    struct CreateOrderParamsAddresses {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialCollateralToken;
        address[] swapPath;
    }

    // @param sizeDeltaUsd for order.sizeDeltaUsd
    // @param triggerPrice for order.triggerPrice
    // @param acceptablePrice for order.acceptablePrice
    // @param executionFee for order.executionFee
    // @param callbackGasLimit for order.callbackGasLimit
    // @param minOutputAmount for order.minOutputAmount
    struct CreateOrderParamsNumbers {
        uint256 sizeDeltaUsd;
        uint256 initialCollateralDeltaAmount;
        uint256 triggerPrice;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 callbackGasLimit;
        uint256 minOutputAmount;
    }

    function isIncrease(IGMXOrder.OrderType _orderType) internal pure returns (bool) {
        if (OrderUtils.isIncreaseOrder(_orderType)) {
            return true;
        } else if (OrderUtils.isDecreaseOrder(_orderType)) {
            return false;
        } else {
            revert InvalidOrderType();
        }
    }

    // @dev check if an orderType is an increase order
    // @param orderType the order type
    // @return whether an orderType is an increase order
    function isIncreaseOrder(IGMXOrder.OrderType orderType) internal pure returns (bool) {
        return orderType == IGMXOrder.OrderType.MarketIncrease ||
               orderType == IGMXOrder.OrderType.LimitIncrease;
    }

    // @dev check if an orderType is a decrease order
    // @param orderType the order type
    // @return whether an orderType is a decrease order
    function isDecreaseOrder(IGMXOrder.OrderType orderType) internal pure returns (bool) {
        return orderType == IGMXOrder.OrderType.MarketDecrease ||
               orderType == IGMXOrder.OrderType.LimitDecrease ||
               orderType == IGMXOrder.OrderType.StopLossDecrease ||
               orderType == IGMXOrder.OrderType.Liquidation;
    }

    // @dev check if an orderType is a liquidation order
    // @param orderType the order type
    // @return whether an orderType is a liquidation order
    function isLiquidationOrder(IGMXOrder.OrderType orderType) internal pure returns (bool) {
        return orderType == IGMXOrder.OrderType.Liquidation;
    }
}
