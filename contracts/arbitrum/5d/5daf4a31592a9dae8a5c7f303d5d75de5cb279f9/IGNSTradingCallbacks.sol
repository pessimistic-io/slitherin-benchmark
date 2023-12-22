// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IGNSTradingStorage.sol";

/**
 * @custom:version 6.4.2
 */
interface IGNSTradingCallbacks {
    struct AggregatorAnswer {
        uint256 orderId;
        uint256 price;
        uint256 spreadP;
        uint256 open;
        uint256 high;
        uint256 low;
    }

    // Useful to avoid stack too deep errors
    struct Values {
        uint256 posDai;
        uint256 levPosDai;
        uint256 tokenPriceDai;
        int256 profitP;
        uint256 price;
        uint256 liqPrice;
        uint256 daiSentToTrader;
        uint256 reward1;
        uint256 reward2;
        uint256 reward3;
        bool exactExecution;
    }

    struct SimplifiedTradeId {
        address trader;
        uint256 pairIndex;
        uint256 index;
        TradeType tradeType;
    }

    struct LastUpdated {
        uint32 tp;
        uint32 sl;
        uint32 limit;
        uint32 created;
    }

    struct TradeData {
        uint40 maxSlippageP; // 1e10 (%)
        uint48 lastOiUpdateTs;
        uint168 _placeholder; // for potential future data
    }

    struct OpenTradePrepInput {
        uint256 executionPrice;
        uint256 wantedPrice;
        uint256 marketPrice;
        uint256 spreadP;
        bool buy;
        uint256 pairIndex;
        uint256 positionSize;
        uint256 leverage;
        uint256 maxSlippageP;
        uint256 tp;
        uint256 sl;
    }

    enum TradeType {
        MARKET,
        LIMIT
    }

    enum CancelReason {
        NONE,
        PAUSED,
        MARKET_CLOSED,
        SLIPPAGE,
        TP_REACHED,
        SL_REACHED,
        EXPOSURE_LIMITS,
        PRICE_IMPACT,
        MAX_LEVERAGE,
        NO_TRADE,
        WRONG_TRADE,
        NOT_HIT
    }

    function openTradeMarketCallback(AggregatorAnswer memory) external;

    function closeTradeMarketCallback(AggregatorAnswer memory) external;

    function executeNftOpenOrderCallback(AggregatorAnswer memory) external;

    function executeNftCloseOrderCallback(AggregatorAnswer memory) external;

    function getTradeLastUpdated(address, uint256, uint256, TradeType) external view returns (LastUpdated memory);

    function setTradeLastUpdated(SimplifiedTradeId calldata, LastUpdated memory) external;

    function setTradeData(SimplifiedTradeId calldata, TradeData memory) external;

    function canExecuteTimeout() external view returns (uint256);

    function pairMaxLeverage(uint256) external view returns (uint256);

    event MarketExecuted(
        uint256 indexed orderId,
        IGNSTradingStorage.Trade t,
        bool open,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeDai,
        int256 percentProfit, // before fees
        uint256 daiSentToTrader
    );

    event LimitExecuted(
        uint256 indexed orderId,
        uint256 limitIndex,
        IGNSTradingStorage.Trade t,
        address indexed nftHolder,
        IGNSTradingStorage.LimitOrder orderType,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeDai,
        int256 percentProfit,
        uint256 daiSentToTrader,
        bool exactExecution
    );

    event MarketOpenCanceled(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        CancelReason cancelReason
    );
    event MarketCloseCanceled(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        CancelReason cancelReason
    );
    event NftOrderCanceled(
        uint256 indexed orderId,
        address indexed nftHolder,
        IGNSTradingStorage.LimitOrder orderType,
        CancelReason cancelReason
    );

    event ClosingFeeSharesPUpdated(uint256 daiVaultFeeP, uint256 lpFeeP, uint256 sssFeeP);

    event Pause(bool paused);
    event Done(bool done);
    event GovFeesClaimed(uint256 valueDai);

    event GovFeeCharged(address indexed trader, uint256 valueDai, bool distributed);
    event ReferralFeeCharged(address indexed trader, uint256 valueDai);
    event TriggerFeeCharged(address indexed trader, uint256 valueDai);
    event SssFeeCharged(address indexed trader, uint256 valueDai);
    event DaiVaultFeeCharged(address indexed trader, uint256 valueDai);
    event BorrowingFeeCharged(address indexed trader, uint256 tradeValueDai, uint256 feeValueDai);
    event PairMaxLeverageUpdated(uint256 indexed pairIndex, uint256 maxLeverage);
}

