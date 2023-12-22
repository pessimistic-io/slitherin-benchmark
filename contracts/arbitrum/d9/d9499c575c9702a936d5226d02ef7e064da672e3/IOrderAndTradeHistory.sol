// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IOrderAndTradeHistory {

    enum ActionType {LIMIT, CANCEL_LIMIT, SYSTEM_CANCEL, OPEN, CLOSE, TP, SL, LIQUIDATED}

    struct OrderInfo {
        address user;
        uint96 amountIn;
        address tokenIn;
        uint80 qty;
        bool isLong;
        address pairBase;
        uint64 entryPrice;
    }

    struct TradeInfo {
        uint96 margin;
        uint96 openFee;
        uint96 executionFee;
        uint40 openTimestamp;
    }

    struct CloseInfo {
        uint64 closePrice;  // 1e8
        int96 fundingFee;   // tokenIn decimals
        uint96 closeFee;    // tokenIn decimals
        int96 pnl;          // tokenIn decimals
        uint96 holdingFee;  // tokenIn decimals
    }

    struct ActionInfo {
        bytes32 hash;
        uint40 timestamp;
        ActionType actionType;
    }

    struct OrderAndTradeHistory {
        bytes32 hash;
        uint40 timestamp;
        string pair;
        ActionType actionType;
        address tokenIn;
        bool isLong;
        uint96 amountIn;           // tokenIn decimals
        uint80 qty;                // 1e10
        uint64 entryPrice;         // 1e8

        uint96 margin;             // tokenIn decimals
        uint96 openFee;            // tokenIn decimals
        uint96 executionFee;       // tokenIn decimals

        uint64 closePrice;         // 1e8
        int96 fundingFee;          // tokenIn decimals
        uint96 closeFee;           // tokenIn decimals
        int96 pnl;                 // tokenIn decimals
        uint96 holdingFee;         // tokenIn decimals
        uint40 openTimestamp;
    }

    function createLimitOrder(bytes32 orderHash, OrderInfo calldata) external;

    function cancelLimitOrder(bytes32 orderHash, ActionType aType) external;

    function limitTrade(bytes32 tradeHash, TradeInfo calldata) external;

    function marketTrade(bytes32 tradeHash, OrderInfo calldata, TradeInfo calldata) external;

    function closeTrade(bytes32 tradeHash, CloseInfo calldata, ActionType aType) external;

    function updateMargin(bytes32 tradeHash, uint96 newMargin) external;

    function getOrderAndTradeHistoryV2(
        address user, uint start, uint8 size
    ) external view returns (OrderAndTradeHistory[] memory);
}

