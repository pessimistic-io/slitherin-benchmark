// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ITradingStorage.sol";
import "./IPairInfos.sol";
import "./IBorrowingFees.sol";
import "./ChainUtils.sol";
import "./TradeUtils.sol";


contract Trading {
    using TradeUtils for address;

    uint256 constant PRECISION = 1e10;
    uint256 constant MAX_SL_P = 75; // -75% PNL

    ITradingStorage public immutable storageT;
    IOrderExecutionTokenManagement public immutable orderTokenManagement;
    IPairInfos public immutable pairInfos;
    IBorrowingFees public immutable borrowingFees;

    uint256 public maxPosStable;
    uint256 public marketOrdersTimeout;

    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    event Done(bool done);
    event Paused(bool paused);

    event NumberUpdated(string name, uint256 value);

    event MarketOrderInitiated(uint256 indexed orderId, address indexed trader, uint256 indexed pairIndex, bool open);

    event OpenLimitPlaced(address indexed trader, uint256 indexed pairIndex, uint256 index);
    event OpenLimitUpdated(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 newPrice,
        uint256 newTp,
        uint256 newSl
    );
    event OpenLimitCanceled(address indexed trader, uint256 indexed pairIndex, uint256 index);

    event TpUpdated(address indexed trader, uint256 indexed pairIndex, uint256 index, uint256 newTp);
    event SlUpdated(address indexed trader, uint256 indexed pairIndex, uint256 index, uint256 newSl);
    event SlUpdateInitiated(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 newSl
    );

    event ChainlinkCallbackTimeout(uint256 indexed orderId, ITradingStorage.PendingMarketOrder order);
    event CouldNotCloseTrade(address indexed trader, uint256 indexed pairIndex, uint256 index);

    error TradingWrongParameters();
    error TradingInvalidGovAddress(address account);
    error TradingDone();
    error TradingInvalidValue(uint256 value);
    error TradingPaused();
    error TradingOverflow();
    error TradingAboveMaxTradesPerPair();
    error TradingAboveMaxPendingOrders(uint256 amount);
    error TradingAboveMaxPos(uint256 amount);
    error TradingBelowMinPos(uint256 amount);
    error TradingInvalidLeverage();
    error TradingWrongTP();
    error TradingWrongSL();
    error TradingPriceImpactTooHigh();
    error TradingIsContract();
    error TradingAlreadyBeingClosed();
    error TradingNoTrade();
    error TradingNoLimitOrder();
    error TradingTooBigSL();
    error TradingTimeout();
    error TradingInvalidOrderOwner();
    error TradingWrongMarketOrderType();
    error TradingHasSL();
    error TradingNoSL();
    error TradingNoTP();

    modifier onlyGov() {
        isGov();
        _;
    }

    modifier notContract() {
        isNotContract();
        _;
    }
    
    modifier notDone() {
        isNotDone();
        _;
    }

    constructor(
        ITradingStorage _storageT,
        IOrderExecutionTokenManagement _orderTokenManagement,
        IPairInfos _pairInfos,
        IBorrowingFees _borrowingFees,
        uint256 _maxPosStable,
        uint256 _marketOrdersTimeout
    ) {
        if (address(_storageT) == address(0) ||
            address(_orderTokenManagement) == address(0) ||
            address(_pairInfos) == address(0) ||
            address(_borrowingFees) == address(0) ||
            _maxPosStable == 0 ||
            _marketOrdersTimeout == 0) {
            revert TradingWrongParameters();
        }

        storageT = _storageT;
        orderTokenManagement = _orderTokenManagement;
        pairInfos = _pairInfos;
        borrowingFees = _borrowingFees;

        maxPosStable = _maxPosStable;
        marketOrdersTimeout = _marketOrdersTimeout;
    }

    function setMaxPosStable(uint256 value) external onlyGov {
        if (value == 0) {
            revert TradingInvalidValue(0);
        }
        maxPosStable = value;
        emit NumberUpdated("maxPosStable", value);
    }

    function setMarketOrdersTimeout(uint256 value) external onlyGov {
        if (value == 0) {
            revert TradingInvalidValue(0);
        }
        marketOrdersTimeout = value;
        emit NumberUpdated("marketOrdersTimeout", value);
    }

    function pause() external onlyGov {
        isPaused = !isPaused;
        emit Paused(isPaused);
    }

    function done() external onlyGov {
        isDone = !isDone;
        emit Done(isDone);
    }

    // Open new trade (MARKET/LIMIT)
    function openTrade(
        ITradingStorage.Trade memory t,
        IOrderExecutionTokenManagement.OpenLimitOrderType orderType, // LEGACY => market
        uint256 slippageP // for market orders only
    ) external notContract notDone {
        if (isPaused) revert TradingPaused();
        if (t.openPrice * slippageP >= type(uint256).max) revert TradingOverflow();

        IAggregator01 aggregator = storageT.priceAggregator();
        IPairsStorage pairsStored = aggregator.pairsStorage();

        address sender = msg.sender;

        if (storageT.openTradesCount(sender, t.pairIndex) +
            storageT.pendingMarketOpenCount(sender, t.pairIndex) +
            storageT.openLimitOrdersCount(sender, t.pairIndex) >=
            storageT.maxTradesPerPair()) {
            revert TradingAboveMaxTradesPerPair();
        }

        if (storageT.pendingOrderIdsCount(sender) >= storageT.maxPendingMarketOrders()) {
            revert TradingAboveMaxPendingOrders(storageT.pendingOrderIdsCount(sender));
        }
        if (t.positionSizeStable > maxPosStable) revert TradingAboveMaxPos(t.positionSizeStable);
        if (t.positionSizeStable * t.leverage < pairsStored.pairMinLevPosStable(t.pairIndex)) {
            revert TradingBelowMinPos(t.positionSizeStable * t.leverage);
        }

        if (t.leverage == 0 ||
            t.leverage < pairsStored.pairMinLeverage(t.pairIndex) ||
            t.leverage > pairMaxLeverage(pairsStored, t.pairIndex)) {
            revert TradingInvalidLeverage();
        }

        if (t.tp != 0 && (t.buy ? t.tp <= t.openPrice : t.tp >= t.openPrice)) revert TradingWrongTP();
        if (t.sl != 0 && (t.buy ? t.sl >= t.openPrice : t.sl <= t.openPrice)) revert TradingWrongSL();

        (uint256 priceImpactP, ) = pairInfos.getTradePriceImpact(0, t.pairIndex, t.buy, t.positionSizeStable * t.leverage);
        if (priceImpactP * t.leverage > pairInfos.maxNegativePnlOnOpenP()) revert TradingPriceImpactTooHigh();

        storageT.transferStable(sender, address(storageT), t.positionSizeStable);

        if (orderType != IOrderExecutionTokenManagement.OpenLimitOrderType.LEGACY) {
            uint256 index = storageT.firstEmptyOpenLimitIndex(sender, t.pairIndex);

            storageT.storeOpenLimitOrder(
                ITradingStorage.OpenLimitOrder(
                    sender,
                    t.pairIndex,
                    index,
                    t.positionSizeStable,
                    t.buy,
                    t.leverage,
                    t.tp,
                    t.sl,
                    t.openPrice,
                    t.openPrice,
                    block.number,
                    0
                )
            );

            orderTokenManagement.setOpenLimitOrderType(sender, t.pairIndex, index, orderType);
            storageT.callbacks().setTradeLastUpdated(
                sender,
                t.pairIndex,
                index,
                ITradingCallbacks01.TradeType.LIMIT,
                ChainUtils.getBlockNumber()
            );

            emit OpenLimitPlaced(sender, t.pairIndex, index);
        } else {
            uint256 orderId = aggregator.getPrice(
                t.pairIndex,
                IAggregator01.OrderType.MARKET_OPEN,
                t.positionSizeStable * t.leverage
            );

            storageT.storePendingMarketOrder(
                ITradingStorage.PendingMarketOrder(
                    ITradingStorage.Trade(
                        sender,
                        t.pairIndex,
                        0,
                        t.positionSizeStable,
                        0,
                        t.buy,
                        t.leverage,
                        t.tp,
                        t.sl
                    ),
                    0,
                    t.openPrice,
                    slippageP,
                    0
                ),
                orderId,
                true
            );

            emit MarketOrderInitiated(orderId, sender, t.pairIndex, true);
        }
    }

    // Close trade (MARKET)
    function closeTradeMarket(uint256 pairIndex, uint256 index) external notContract notDone {
        address sender = msg.sender;

        ITradingStorage.Trade memory t = storageT.openTrades(sender, pairIndex, index);
        ITradingStorage.TradeInfo memory i = storageT.openTradesInfo(sender, pairIndex, index);

        if (storageT.pendingOrderIdsCount(sender) >= storageT.maxPendingMarketOrders()) {
            revert TradingAboveMaxPendingOrders(storageT.pendingOrderIdsCount(sender));
        }
        if (i.beingMarketClosed) revert TradingAlreadyBeingClosed();
        if (t.leverage == 0) revert TradingNoTrade();

        uint256 orderId = storageT.priceAggregator().getPrice(
            pairIndex,
            IAggregator01.OrderType.MARKET_CLOSE,
            (t.positionSizeStable * t.leverage) / PRECISION
        );

        storageT.storePendingMarketOrder(
            ITradingStorage.PendingMarketOrder(
                ITradingStorage.Trade(sender, pairIndex, index, 0, 0, false, 0, 0, 0),
                0,
                0,
                0,
                0
            ),
            orderId,
            false
        );

        emit MarketOrderInitiated(orderId, sender, pairIndex, false);
    }

    // Manage limit order (OPEN)
    function updateOpenLimitOrder(
        uint256 pairIndex,
        uint256 index,
        uint256 price,
        uint256 tp,
        uint256 sl
    ) external notContract notDone {
        address sender = msg.sender;
        if (!storageT.hasOpenLimitOrder(sender, pairIndex, index)) revert TradingNoLimitOrder();

        ITradingStorage.OpenLimitOrder memory o = storageT.getOpenLimitOrder(sender, pairIndex, index);

        if (tp != 0 && (o.buy ? tp <= price : tp >= price)) revert TradingWrongTP();
        if (sl != 0 && (o.buy ? sl >= price : sl <= price)) revert TradingWrongSL();

        o.minPrice = price;
        o.maxPrice = price;
        o.tp = tp;
        o.sl = sl;

        storageT.updateOpenLimitOrder(o);
        storageT.callbacks().setTradeLastUpdated(
            sender,
            pairIndex,
            index,
            ITradingCallbacks01.TradeType.LIMIT,
            ChainUtils.getBlockNumber()
        );

        emit OpenLimitUpdated(sender, pairIndex, index, price, tp, sl);
    }

    function cancelOpenLimitOrder(uint256 pairIndex, uint256 index) external notContract notDone {
        address sender = msg.sender;
        if (!storageT.hasOpenLimitOrder(sender, pairIndex, index)) revert TradingNoLimitOrder();

        ITradingStorage.OpenLimitOrder memory o = storageT.getOpenLimitOrder(sender, pairIndex, index);

        storageT.unregisterOpenLimitOrder(sender, pairIndex, index);
        storageT.transferStable(address(storageT), sender, o.positionSize);

        emit OpenLimitCanceled(sender, pairIndex, index);
    }

    // Manage limit order (TP/SL)
    function updateTp(uint256 pairIndex, uint256 index, uint256 newTp) external notContract notDone {
        address sender = msg.sender;

        ITradingStorage.Trade memory t = storageT.openTrades(sender, pairIndex, index);
        if (t.leverage == 0) revert TradingNoTrade();

        storageT.updateTp(sender, pairIndex, index, newTp);
        storageT.callbacks().setTpLastUpdated(
            sender,
            pairIndex,
            index,
            ITradingCallbacks01.TradeType.MARKET,
            ChainUtils.getBlockNumber()
        );

        emit TpUpdated(sender, pairIndex, index, newTp);
    }

    function updateSl(uint256 pairIndex, uint256 index, uint256 newSl) external notContract notDone {
        address sender = msg.sender;

        ITradingStorage.Trade memory t = storageT.openTrades(sender, pairIndex, index);

        if (t.leverage == 0) revert TradingNoTrade();

        uint256 maxSlDist = (t.openPrice * MAX_SL_P) / 100 / t.leverage;

        if (newSl != 0 && (t.buy ? newSl < t.openPrice - maxSlDist : newSl > t.openPrice + maxSlDist)) {
            revert TradingTooBigSL();
        }

        IAggregator01 aggregator = storageT.priceAggregator();

        if (newSl == 0 || !aggregator.pairsStorage().guaranteedSlEnabled(pairIndex)) {
            storageT.updateSl(sender, pairIndex, index, newSl);
            storageT.callbacks().setSlLastUpdated(
                sender,
                pairIndex,
                index,
                ITradingCallbacks01.TradeType.MARKET,
                ChainUtils.getBlockNumber()
            );

            emit SlUpdated(sender, pairIndex, index, newSl);
        } else {
            uint256 orderId = aggregator.getPrice(
                pairIndex,
                IAggregator01.OrderType.UPDATE_SL,
                (t.positionSizeStable * t.leverage) / PRECISION
            );

            aggregator.storePendingSlOrder(
                orderId,
                IAggregator01.PendingSl(sender, pairIndex, index, t.openPrice, t.buy, newSl)
            );

            emit SlUpdateInitiated(orderId, sender, pairIndex, index, newSl);
        }
    }

    // Execute limit order
    function executeBotOrder(
        ITradingStorage.LimitOrder orderType,
        address trader,
        uint256 pairIndex,
        uint256 index
    ) external notContract notDone {
        if (!canExecute(
                orderType,
                ITradingCallbacks01.SimplifiedTradeId(
                    trader,
                    pairIndex,
                    index,
                    orderType == ITradingStorage.LimitOrder.OPEN
                        ? ITradingCallbacks01.TradeType.LIMIT
                        : ITradingCallbacks01.TradeType.MARKET
                )
        )) {
            revert TradingTimeout();
        }

        ITradingStorage.Trade memory t;

        if (orderType == ITradingStorage.LimitOrder.OPEN) {
            if (!storageT.hasOpenLimitOrder(trader, pairIndex, index)) revert TradingNoLimitOrder();
        } else {
            t = storageT.openTrades(trader, pairIndex, index);

            if (t.leverage == 0) revert TradingNoTrade();

            if (orderType == ITradingStorage.LimitOrder.LIQ) {
                uint256 liqPrice = borrowingFees.getTradeLiquidationPrice(
                    IBorrowingFees.LiqPriceInput(
                        t.trader,
                        t.pairIndex,
                        t.index,
                        t.openPrice,
                        t.buy,
                        t.positionSizeStable,
                        t.leverage
                    )
                );

                if (t.sl != 0 && (t.buy ? liqPrice <= t.sl : liqPrice >= t.sl)) revert TradingHasSL();
            } else {
                if (orderType == ITradingStorage.LimitOrder.SL && t.sl == 0) revert TradingNoSL();
                if (orderType == ITradingStorage.LimitOrder.TP && t.tp == 0) revert TradingNoTP();
            }
        }

        uint256 leveragedPosStable;

        if (orderType == ITradingStorage.LimitOrder.OPEN) {
            ITradingStorage.OpenLimitOrder memory l = storageT.getOpenLimitOrder(trader, pairIndex, index);

            leveragedPosStable = l.positionSize * l.leverage;
            (uint256 priceImpactP, ) = pairInfos.getTradePriceImpact(0, l.pairIndex, l.buy, leveragedPosStable);

            if (priceImpactP * l.leverage > pairInfos.maxNegativePnlOnOpenP()) revert TradingPriceImpactTooHigh();
        } else {
            leveragedPosStable = t.positionSizeStable * t.leverage;
        }

        IAggregator01 aggregator = storageT.priceAggregator();
        uint256 orderId = aggregator.getPrice(
            pairIndex,
            orderType == ITradingStorage.LimitOrder.OPEN
                ? IAggregator01.OrderType.LIMIT_OPEN
                : IAggregator01.OrderType.LIMIT_CLOSE,
            leveragedPosStable
        );

        storageT.storePendingBotOrder(
            ITradingStorage.PendingBotOrder(trader, pairIndex, index, orderType),
            orderId
        );
    }

    function openTradeMarketTimeout(uint256 _order) external notContract notDone {
        address sender = msg.sender;

        ITradingStorage.PendingMarketOrder memory o = storageT.reqID_pendingMarketOrder(_order);
        ITradingStorage.Trade memory t = o.trade;

        if (o.block == 0 || block.number < o.block + marketOrdersTimeout) revert TradingTimeout();
        if (t.trader != sender) revert TradingInvalidOrderOwner();
        if (t.leverage == 0) revert TradingWrongMarketOrderType();

        storageT.unregisterPendingMarketOrder(_order, true);
        storageT.transferStable(address(storageT), sender, t.positionSizeStable);

        emit ChainlinkCallbackTimeout(_order, o);
    }

    function closeTradeMarketTimeout(uint256 _order) external notContract notDone {
        address sender = msg.sender;

        ITradingStorage.PendingMarketOrder memory o = storageT.reqID_pendingMarketOrder(_order);
        ITradingStorage.Trade memory t = o.trade;

        if (o.block == 0 || block.number < o.block + marketOrdersTimeout) revert TradingTimeout();
        if (t.trader != sender) revert TradingInvalidOrderOwner();
        if (t.leverage > 0) revert TradingWrongMarketOrderType();

        storageT.unregisterPendingMarketOrder(_order, false);

        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSignature("closeTradeMarket(uint256,uint256)", t.pairIndex, t.index)
        );

        if (!success) {
            emit CouldNotCloseTrade(sender, t.pairIndex, t.index);
        }

        emit ChainlinkCallbackTimeout(_order, o);
    }

    function canExecute(
        ITradingStorage.LimitOrder orderType,
        ITradingCallbacks01.SimplifiedTradeId memory id
    ) private view returns (bool) {
        if (orderType == ITradingStorage.LimitOrder.LIQ) return true;

        uint256 b = ChainUtils.getBlockNumber();
        address cb = storageT.callbacks();

        if (orderType == ITradingStorage.LimitOrder.TP) return !cb.isTpInTimeout(id, b);
        if (orderType == ITradingStorage.LimitOrder.SL) return !cb.isSlInTimeout(id, b);

        return !cb.isLimitInTimeout(id, b);
    }

    function pairMaxLeverage(IPairsStorage pairsStored, uint256 pairIndex) private view returns (uint256) {
        uint256 max = ITradingCallbacks01(storageT.callbacks()).pairMaxLeverage(pairIndex);
        return max > 0 ? max : pairsStored.pairMaxLeverage(pairIndex);
    }

    function isGov() private view {
        if (msg.sender != storageT.gov()) {
            revert TradingInvalidGovAddress(msg.sender);
        }
    }

    function isNotContract() private view {
        if (tx.origin != msg.sender) revert TradingIsContract();
    }

    function isNotDone() private view {
        if (isDone) revert TradingDone();
    }
}

