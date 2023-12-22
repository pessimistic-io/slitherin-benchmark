// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGambitTradingCallbacksV1 {
    struct AggregatorAnswer {
        uint orderId;
        uint price;
        uint conf;
        uint confMultiplierP;
    }

    function openTradeMarketCallback(AggregatorAnswer memory) external;

    function closeTradeMarketCallback(AggregatorAnswer memory) external;

    function executeNftOpenOrderCallback(AggregatorAnswer memory) external;

    function executeNftCloseOrderCallback(AggregatorAnswer memory) external;

    function updateSlCallback(AggregatorAnswer memory) external;

    function removeCollateralCallback(AggregatorAnswer memory) external;
}

