// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPyth.sol";
import "./IERC20.sol";

import "./ISimpleGToken.sol";
import "./IGambitPairsStorageV1.sol";

import "./TokenInterfaceV5.sol";
import "./NftInterfaceV5.sol";

interface PausableInterfaceV5 {
    function isPaused() external view returns (bool);
}

interface IGambitTradingStorageV1 {
    enum LimitOrder {
        TP,
        SL,
        LIQ,
        OPEN
    }
    struct Trade {
        address trader;
        uint pairIndex;
        uint index;
        uint initialPosToken; // 1e18
        uint positionSizeUsdc; // 1e6 (USDC) or 1e18 (DAI)
        uint openPrice; // PRECISION
        bool buy;
        uint leverage; // 1e18
        uint tp; // PRECISION
        uint sl; // PRECISION
    }
    struct TradeInfo {
        uint tokenId;
        uint tokenPriceUsdc; // PRECISION
        uint openInterestUsdc; // 1e6 (USDC) or 1e18 (DAI)
        uint tpLastUpdated;
        uint slLastUpdated;
        bool beingMarketClosed;
    }
    struct OpenLimitOrder {
        address trader;
        uint pairIndex;
        uint index;
        uint positionSize; // 1e6 (USDC) or 1e18 (DAI)
        uint spreadReductionP;
        bool buy;
        uint leverage; // 1e18
        uint tp; // PRECISION (%)
        uint sl; // PRECISION (%)
        uint minPrice; // PRECISION
        uint maxPrice; // PRECISION
        uint block;
        uint tokenId; // index in supportedTokens
    }
    struct PendingMarketOrder {
        Trade trade;
        uint block;
        uint wantedPrice; // PRECISION
        uint slippageP; // PRECISION (%)
        uint spreadReductionP;
        uint tokenId; // index in supportedTokens
    }
    struct PendingNftOrder {
        address nftHolder;
        uint nftId;
        address trader;
        uint pairIndex;
        uint index;
        LimitOrder orderType;
    }
    struct PendingRemoveCollateralOrder {
        address trader;
        uint pairIndex;
        uint index;
        uint amount;
        uint openPrice;
        bool buy;
    }

    function PRECISION() external pure returns (uint);

    function gov() external view returns (address);

    function dev() external view returns (address);

    function usdc() external view returns (IERC20);

    function usdcDecimals() external view returns (uint8);

    function token() external view returns (TokenInterfaceV5);

    function priceAggregator() external view returns (AggregatorInterfaceV6_2);

    function vault() external view returns (ISimpleGToken);

    function trading() external view returns (address);

    function callbacks() external view returns (address);

    function handleTokens(address, uint, bool) external;

    function transferUsdc(address, address, uint) external;

    function unregisterTrade(address, uint, uint) external;

    function unregisterPendingMarketOrder(uint, bool) external;

    function unregisterOpenLimitOrder(address, uint, uint) external;

    function hasOpenLimitOrder(
        address,
        uint,
        uint
    ) external view returns (bool);

    function storePendingMarketOrder(
        PendingMarketOrder memory,
        uint,
        bool
    ) external;

    function openTrades(
        address,
        uint,
        uint
    ) external view returns (Trade memory);

    function openTradesInfo(
        address,
        uint,
        uint
    ) external view returns (TradeInfo memory);

    function updateSl(address, uint, uint, uint) external;

    function updateTp(address, uint, uint, uint) external;

    function getOpenLimitOrder(
        address,
        uint,
        uint
    ) external view returns (OpenLimitOrder memory);

    function spreadReductionsP(uint) external view returns (uint);

    function storeOpenLimitOrder(OpenLimitOrder memory) external;

    function reqID_pendingMarketOrder(
        uint
    ) external view returns (PendingMarketOrder memory);

    function storePendingNftOrder(PendingNftOrder memory, uint) external;

    function updateOpenLimitOrder(OpenLimitOrder calldata) external;

    function reqID_pendingRemoveCollateralOrder(
        uint
    ) external view returns (PendingRemoveCollateralOrder memory);

    function storePendingRemoveCollateralOrder(
        PendingRemoveCollateralOrder memory,
        uint
    ) external;

    function unregisterPendingRemoveCollateralOrder(uint) external;

    function firstEmptyTradeIndex(address, uint) external view returns (uint);

    function firstEmptyOpenLimitIndex(
        address,
        uint
    ) external view returns (uint);

    function increaseNftRewards(uint, uint) external;

    function nftSuccessTimelock() external view returns (uint);

    function reqID_pendingNftOrder(
        uint
    ) external view returns (PendingNftOrder memory);

    function updateTrade(Trade memory) external;

    function nftLastSuccess(uint) external view returns (uint);

    function unregisterPendingNftOrder(uint) external;

    function handleDevGovFees(uint, uint, bool) external returns (uint);

    function handleGovFee(uint) external;

    function getDevGovFees(uint, uint, bool) external view returns (uint);

    function distributeLpRewards(uint) external;

    function storeTrade(Trade memory, TradeInfo memory) external;

    function openLimitOrdersCount(address, uint) external view returns (uint);

    function openTradesCount(address, uint) external view returns (uint);

    function pendingMarketOpenCount(address, uint) external view returns (uint);

    function pendingMarketCloseCount(
        address,
        uint
    ) external view returns (uint);

    function maxTradesPerPair() external view returns (uint);

    function pendingOrderIdsCount(address) external view returns (uint);

    function maxPendingMarketOrders() external view returns (uint);

    function openInterestUsdc(uint, uint) external view returns (uint);

    function openInterestToken(uint, uint) external view returns (uint);

    function getPendingOrderIds(address) external view returns (uint[] memory);

    function nfts(uint) external view returns (NftInterfaceV5);

    function fakeBlockNumber() external view returns (uint); // Testing
}

interface AggregatorInterfaceV6_2 {
    enum OrderType {
        MARKET_OPEN,
        MARKET_CLOSE,
        LIMIT_OPEN,
        LIMIT_CLOSE,
        UPDATE_SL,
        REMOVE_COLLATERAL
    }

    function pyth() external returns (IPyth);

    function PYTH_PRICE_AGE() external returns (uint);

    function pairsStorage() external view returns (IGambitPairsStorageV1);

    function getPrice(uint, OrderType, uint) external returns (uint);

    function fulfill(
        uint orderId,
        PythStructs.Price calldata pythPrice
    ) external payable returns (uint256 price, uint256 conf, bool success);

    function tokenPriceUsdc() external returns (uint);

    function openFeeP(uint) external view returns (uint);

    function pendingSlOrders(uint) external view returns (PendingSl memory);

    function storePendingSlOrder(uint orderId, PendingSl calldata p) external;

    function unregisterPendingSlOrder(uint orderId) external;

    struct PendingSl {
        address trader;
        uint pairIndex;
        uint index;
        uint openPrice;
        bool buy;
        uint newSl;
    }
}

interface NftRewardsInterfaceV6 {
    struct TriggeredLimitId {
        address trader;
        uint pairIndex;
        uint index;
        IGambitTradingStorageV1.LimitOrder order;
    }
    enum OpenLimitOrderType {
        LEGACY,
        REVERSAL,
        MOMENTUM
    }

    function storeFirstToTrigger(TriggeredLimitId calldata, address) external;

    function storeTriggerSameBlock(TriggeredLimitId calldata, address) external;

    function unregisterTrigger(TriggeredLimitId calldata) external;

    function distributeNftReward(TriggeredLimitId calldata, uint) external;

    function openLimitOrderTypes(
        address,
        uint,
        uint
    ) external view returns (OpenLimitOrderType);

    function setOpenLimitOrderType(
        address,
        uint,
        uint,
        OpenLimitOrderType
    ) external;

    function triggered(TriggeredLimitId calldata) external view returns (bool);

    function timedOut(TriggeredLimitId calldata) external view returns (bool);
}

