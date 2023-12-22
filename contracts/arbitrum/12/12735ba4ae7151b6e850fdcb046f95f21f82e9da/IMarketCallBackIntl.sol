// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./MarketDataTypes.sol";
import "./PositionStruct.sol";

interface MarketCallBackIntl {
    struct Calls {
        bool updatePosition;
        bool updateOrder;
        bool deleteOrder;
    }

    function getHooksCalls() external pure returns (Calls memory);
}

interface MarketPositionCallBackIntl is MarketCallBackIntl {
    //=====================================
    //      UPDATE POSITION
    //=====================================
    struct UpdatePositionEvent {
        MarketDataTypes.UpdatePositionInputs inputs;
        Position.Props position;
        int256[] fees;
        address collateralToken;
        address indexToken;
        int256 collateralDeltaAfter;
    }

    function updatePositionCallback(UpdatePositionEvent memory _event) external;
}

interface MarketOrderCallBackIntl is MarketCallBackIntl {
    //=====================================
    //      UPDATE ORDER
    //=====================================
    function updateOrderCallback(
        MarketDataTypes.UpdateOrderInputs memory _event
    ) external;

    //=====================================
    //      DEL ORDER
    //=====================================
    struct DeleteOrderEvent {
        Order.Props order;
        MarketDataTypes.UpdatePositionInputs inputs;
        uint8 reason;
        string reasonStr;
        int256 dPNL;
    }
    function deleteOrderCallback(DeleteOrderEvent memory e) external;
}

