// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ITradingCallbacks{

    struct AggregatorAnswer{ uint256 orderId; uint256 price; uint256 spreadP; }
    
    function openTradeMarketCallback(AggregatorAnswer memory) external;
    function closeTradeMarketCallback(AggregatorAnswer memory) external;
    function executeBotOpenOrderCallback(AggregatorAnswer memory) external;
    function executeBotCloseOrderCallback(AggregatorAnswer memory) external;
    function updateSlCallback(AggregatorAnswer memory) external;
}

