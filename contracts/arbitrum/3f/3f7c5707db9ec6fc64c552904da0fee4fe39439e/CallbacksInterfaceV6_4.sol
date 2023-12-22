// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface CallbacksInterfaceV6_4 {
    struct AggregatorAnswer {
        uint orderId;
        uint price;
        uint spreadP;
        uint64 open;
        uint64 high;
        uint64 low;
    }

    function openTradeMarketCallback(AggregatorAnswer memory) external;

    function closeTradeMarketCallback(AggregatorAnswer memory) external;

    function executeNftOpenOrderCallback(AggregatorAnswer memory) external;

    function executeNftCloseOrderCallback(AggregatorAnswer memory) external;
}

