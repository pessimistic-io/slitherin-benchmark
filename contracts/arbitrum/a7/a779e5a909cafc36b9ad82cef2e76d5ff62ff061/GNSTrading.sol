// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Initializable} from "./Initializable.sol";

import "./IGNSTrading.sol";
import "./IGNSPairInfos.sol";
import "./IGNSReferrals.sol";
import "./IGNSBorrowingFees.sol";
import "./IGNSOracleRewards.sol";

import "./ChainUtils.sol";
import "./TradeUtils.sol";
import "./PackingUtils.sol";

import "./Delegatable.sol";

/**
 * @custom:version 6.4.2
 * @custom:oz-upgrades-unsafe-allow external-library-linking delegatecall
 */
contract GNSTrading is Initializable, Delegatable, IGNSTrading {
    using TradeUtils for address;
    using PackingUtils for uint256;

    // Contracts (constant)
    IGNSTradingStorage public storageT;
    IGNSOracleRewards public oracleRewards;
    IGNSPairInfos public pairInfos;
    IGNSReferrals public referrals;
    IGNSBorrowingFees public borrowingFees;

    // Params (constant)
    uint256 private constant PRECISION = 1e10;
    uint256 private constant MAX_SL_P = 75; // -75% PNL

    // Params (adjustable)
    uint256 public maxPosDai; // 1e18 (eg. 75000 * 1e18)
    uint256 public marketOrdersTimeout; // block (eg. 30)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    mapping(address => bool) public bypassTriggerLink; // Doesn't have to pay link in executeNftOrder()

    function initialize(
        IGNSTradingStorage _storageT,
        IGNSOracleRewards _oracleRewards,
        IGNSPairInfos _pairInfos,
        IGNSReferrals _referrals,
        IGNSBorrowingFees _borrowingFees,
        uint256 _maxPosDai,
        uint256 _marketOrdersTimeout
    ) external initializer {
        require(
            address(_storageT) != address(0) &&
                address(_oracleRewards) != address(0) &&
                address(_pairInfos) != address(0) &&
                address(_referrals) != address(0) &&
                address(_borrowingFees) != address(0) &&
                _maxPosDai > 0 &&
                _marketOrdersTimeout > 0,
            "WRONG_PARAMS"
        );

        storageT = _storageT;
        oracleRewards = _oracleRewards;
        pairInfos = _pairInfos;
        referrals = _referrals;
        borrowingFees = _borrowingFees;

        maxPosDai = _maxPosDai;
        marketOrdersTimeout = _marketOrdersTimeout;
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier notContract() {
        require(tx.origin == msg.sender);
        _;
    }
    modifier notDone() {
        require(!isDone, "DONE");
        _;
    }

    // Manage params
    function setMaxPosDai(uint256 value) external onlyGov {
        require(value > 0, "VALUE_0");
        maxPosDai = value;
        emit NumberUpdated("maxPosDai", value);
    }

    function setMarketOrdersTimeout(uint256 value) external onlyGov {
        require(value > 0, "VALUE_0");
        marketOrdersTimeout = value;
        emit NumberUpdated("marketOrdersTimeout", value);
    }

    function setBypassTriggerLink(address user, bool bypass) external onlyGov {
        bypassTriggerLink[user] = bypass;

        emit BypassTriggerLinkUpdated(user, bypass);
    }

    // Manage state
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
        IGNSTradingStorage.Trade memory t,
        IGNSOracleRewards.OpenLimitOrderType orderType, // LEGACY => market
        uint256 slippageP, // 1e10 (%)
        address referrer
    ) external notContract notDone {
        require(!isPaused, "PAUSED");
        require(t.openPrice * slippageP < type(uint256).max, "OVERFLOW");
        require(t.openPrice > 0, "PRICE_ZERO");

        IGNSPriceAggregator aggregator = storageT.priceAggregator();
        IGNSPairsStorage pairsStored = IGNSPairsStorage(aggregator.pairsStorage());

        address sender = _msgSender();

        require(
            storageT.openTradesCount(sender, t.pairIndex) +
                storageT.pendingMarketOpenCount(sender, t.pairIndex) +
                storageT.openLimitOrdersCount(sender, t.pairIndex) <
                storageT.maxTradesPerPair(),
            "MAX_TRADES_PER_PAIR"
        );

        require(storageT.pendingOrderIdsCount(sender) < storageT.maxPendingMarketOrders(), "MAX_PENDING_ORDERS");
        require(t.positionSizeDai <= maxPosDai, "ABOVE_MAX_POS");

        uint levPosDai = t.positionSizeDai * t.leverage;
        require(
            storageT.openInterestDai(t.pairIndex, t.buy ? 0 : 1) + levPosDai <=
                borrowingFees.getPairMaxOi(t.pairIndex) * 1e8,
            "ABOVE_PAIR_MAX_OI"
        );
        require(borrowingFees.withinMaxGroupOi(t.pairIndex, t.buy, levPosDai), "ABOVE_GROUP_MAX_OI");
        require(levPosDai >= pairsStored.pairMinLevPosDai(t.pairIndex), "BELOW_MIN_POS");

        require(
            t.leverage > 0 &&
                t.leverage >= pairsStored.pairMinLeverage(t.pairIndex) &&
                t.leverage <= _pairMaxLeverage(pairsStored, t.pairIndex),
            "LEVERAGE_INCORRECT"
        );

        require(t.tp == 0 || (t.buy ? t.tp > t.openPrice : t.tp < t.openPrice), "WRONG_TP");
        require(t.sl == 0 || (t.buy ? t.sl < t.openPrice : t.sl > t.openPrice), "WRONG_SL");

        (uint256 priceImpactP, ) = borrowingFees.getTradePriceImpact(0, t.pairIndex, t.buy, levPosDai);
        require(priceImpactP * t.leverage <= pairInfos.maxNegativePnlOnOpenP(), "PRICE_IMPACT_TOO_HIGH");

        storageT.transferDai(sender, address(storageT), t.positionSizeDai);

        if (orderType != IGNSOracleRewards.OpenLimitOrderType.LEGACY) {
            uint256 index = storageT.firstEmptyOpenLimitIndex(sender, t.pairIndex);

            storageT.storeOpenLimitOrder(
                IGNSTradingStorage.OpenLimitOrder(
                    sender,
                    t.pairIndex,
                    index,
                    t.positionSizeDai,
                    0,
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

            oracleRewards.setOpenLimitOrderType(sender, t.pairIndex, index, orderType);

            address c = storageT.callbacks();
            c.setTradeLastUpdated(
                sender,
                t.pairIndex,
                index,
                IGNSTradingCallbacks.TradeType.LIMIT,
                ChainUtils.getBlockNumber()
            );
            c.setLimitMaxSlippageP(sender, t.pairIndex, index, slippageP);

            emit OpenLimitPlaced(sender, t.pairIndex, index);
        } else {
            uint256 orderId = aggregator.getPrice(
                t.pairIndex,
                IGNSPriceAggregator.OrderType.MARKET_OPEN,
                levPosDai,
                ChainUtils.getBlockNumber()
            );

            storageT.storePendingMarketOrder(
                IGNSTradingStorage.PendingMarketOrder(
                    IGNSTradingStorage.Trade(
                        sender,
                        t.pairIndex,
                        0,
                        0,
                        t.positionSizeDai,
                        0,
                        t.buy,
                        t.leverage,
                        t.tp,
                        t.sl
                    ),
                    0,
                    t.openPrice,
                    slippageP,
                    0,
                    0
                ),
                orderId,
                true
            );

            emit MarketOrderInitiated(orderId, sender, t.pairIndex, true);
        }

        referrals.registerPotentialReferrer(sender, referrer);
    }

    // Close trade (MARKET)
    function closeTradeMarket(uint256 pairIndex, uint256 index) external notContract notDone {
        address sender = _msgSender();

        IGNSTradingStorage.Trade memory t = storageT.openTrades(sender, pairIndex, index);
        IGNSTradingStorage.TradeInfo memory i = storageT.openTradesInfo(sender, pairIndex, index);

        require(storageT.pendingOrderIdsCount(sender) < storageT.maxPendingMarketOrders(), "MAX_PENDING_ORDERS");
        require(!i.beingMarketClosed, "ALREADY_BEING_CLOSED");
        require(t.leverage > 0, "NO_TRADE");

        uint256 orderId = storageT.priceAggregator().getPrice(
            pairIndex,
            IGNSPriceAggregator.OrderType.MARKET_CLOSE,
            (t.initialPosToken * i.tokenPriceDai * t.leverage) / PRECISION,
            ChainUtils.getBlockNumber()
        );

        storageT.storePendingMarketOrder(
            IGNSTradingStorage.PendingMarketOrder(
                IGNSTradingStorage.Trade(sender, pairIndex, index, 0, 0, 0, false, 0, 0, 0),
                0,
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
        uint256 price, // PRECISION
        uint256 tp,
        uint256 sl,
        uint256 maxSlippageP
    ) external notContract notDone {
        require(price > 0, "PRICE_ZERO");

        address sender = _msgSender();
        require(storageT.hasOpenLimitOrder(sender, pairIndex, index), "NO_LIMIT");

        IGNSTradingStorage.OpenLimitOrder memory o = storageT.getOpenLimitOrder(sender, pairIndex, index);

        require(tp == 0 || (o.buy ? tp > price : tp < price), "WRONG_TP");
        require(sl == 0 || (o.buy ? sl < price : sl > price), "WRONG_SL");

        require(price * maxSlippageP < type(uint256).max, "OVERFLOW");

        _checkNoPendingTrigger(sender, pairIndex, index, IGNSTradingStorage.LimitOrder.OPEN);

        o.minPrice = price;
        o.maxPrice = price;
        o.tp = tp;
        o.sl = sl;

        storageT.updateOpenLimitOrder(o);

        address c = storageT.callbacks();
        c.setTradeLastUpdated(
            sender,
            pairIndex,
            index,
            IGNSTradingCallbacks.TradeType.LIMIT,
            ChainUtils.getBlockNumber()
        );
        c.setLimitMaxSlippageP(sender, pairIndex, index, maxSlippageP);

        emit OpenLimitUpdated(sender, pairIndex, index, price, tp, sl, maxSlippageP);
    }

    function cancelOpenLimitOrder(uint256 pairIndex, uint256 index) external notContract notDone {
        address sender = _msgSender();
        require(storageT.hasOpenLimitOrder(sender, pairIndex, index), "NO_LIMIT");

        IGNSTradingStorage.OpenLimitOrder memory o = storageT.getOpenLimitOrder(sender, pairIndex, index);

        _checkNoPendingTrigger(sender, pairIndex, index, IGNSTradingStorage.LimitOrder.OPEN);

        storageT.unregisterOpenLimitOrder(sender, pairIndex, index);
        storageT.transferDai(address(storageT), sender, o.positionSize);

        emit OpenLimitCanceled(sender, pairIndex, index);
    }

    // Manage limit order (TP/SL)
    function updateTp(uint256 pairIndex, uint256 index, uint256 newTp) external notContract notDone {
        address sender = _msgSender();

        _checkNoPendingTrigger(sender, pairIndex, index, IGNSTradingStorage.LimitOrder.TP);

        IGNSTradingStorage.Trade memory t = storageT.openTrades(sender, pairIndex, index);
        require(t.leverage > 0, "NO_TRADE");

        storageT.updateTp(sender, pairIndex, index, newTp);
        storageT.callbacks().setTpLastUpdated(
            sender,
            pairIndex,
            index,
            IGNSTradingCallbacks.TradeType.MARKET,
            ChainUtils.getBlockNumber()
        );

        emit TpUpdated(sender, pairIndex, index, newTp);
    }

    function updateSl(uint256 pairIndex, uint256 index, uint256 newSl) external notContract notDone {
        address sender = _msgSender();

        _checkNoPendingTrigger(sender, pairIndex, index, IGNSTradingStorage.LimitOrder.SL);

        IGNSTradingStorage.Trade memory t = storageT.openTrades(sender, pairIndex, index);
        require(t.leverage > 0, "NO_TRADE");

        uint256 maxSlDist = (t.openPrice * MAX_SL_P) / 100 / t.leverage;

        require(
            newSl == 0 || (t.buy ? newSl >= t.openPrice - maxSlDist : newSl <= t.openPrice + maxSlDist),
            "SL_TOO_BIG"
        );

        storageT.updateSl(sender, pairIndex, index, newSl);
        storageT.callbacks().setSlLastUpdated(
            sender,
            pairIndex,
            index,
            IGNSTradingCallbacks.TradeType.MARKET,
            ChainUtils.getBlockNumber()
        );

        emit SlUpdated(sender, pairIndex, index, newSl);
    }

    // Execute limit order
    function executeNftOrder(uint256 packed) external notContract notDone {
        (uint256 _orderType, address trader, uint256 pairIndex, uint256 index, , ) = packed.unpackExecuteNftOrder();

        IGNSTradingStorage.LimitOrder orderType = IGNSTradingStorage.LimitOrder(_orderType);
        bool isOpenLimit = orderType == IGNSTradingStorage.LimitOrder.OPEN;

        IGNSTradingStorage.Trade memory t;

        if (isOpenLimit) {
            require(storageT.hasOpenLimitOrder(trader, pairIndex, index), "NO_LIMIT");
        } else {
            t = storageT.openTrades(trader, pairIndex, index);

            require(t.leverage > 0, "NO_TRADE");

            if (orderType == IGNSTradingStorage.LimitOrder.LIQ) {
                if (t.sl > 0) {
                    uint256 liqPrice = borrowingFees.getTradeLiquidationPrice(
                        IGNSBorrowingFees.LiqPriceInput(
                            t.trader,
                            t.pairIndex,
                            t.index,
                            t.openPrice,
                            t.buy,
                            (t.initialPosToken *
                                storageT.openTradesInfo(t.trader, t.pairIndex, t.index).tokenPriceDai) / PRECISION,
                            t.leverage
                        )
                    );

                    // If liq price not closer than SL, turn order into a SL order
                    if ((t.buy && liqPrice <= t.sl) || (!t.buy && liqPrice >= t.sl)) {
                        orderType = IGNSTradingStorage.LimitOrder.SL;
                    }
                }
            } else {
                require(orderType != IGNSTradingStorage.LimitOrder.SL || t.sl > 0, "NO_SL");
                require(orderType != IGNSTradingStorage.LimitOrder.TP || t.tp > 0, "NO_TP");
            }
        }

        IGNSOracleRewards.TriggeredLimitId memory triggeredLimitId = _checkNoPendingTrigger(
            trader,
            pairIndex,
            index,
            orderType
        );

        address sender = _msgSender();
        bool byPassesLinkCost = bypassTriggerLink[sender];

        uint256 leveragedPosDai;

        if (isOpenLimit) {
            IGNSTradingStorage.OpenLimitOrder memory l = storageT.getOpenLimitOrder(trader, pairIndex, index);

            uint256 _leveragedPosDai = l.positionSize * l.leverage;
            (uint256 priceImpactP, ) = borrowingFees.getTradePriceImpact(0, l.pairIndex, l.buy, _leveragedPosDai);

            require(priceImpactP * l.leverage <= pairInfos.maxNegativePnlOnOpenP(), "PRICE_IMPACT_TOO_HIGH");

            if (!byPassesLinkCost) {
                leveragedPosDai = _leveragedPosDai;
            }
        } else if (!byPassesLinkCost) {
            leveragedPosDai =
                (t.initialPosToken * storageT.openTradesInfo(trader, pairIndex, index).tokenPriceDai * t.leverage) /
                PRECISION;
        }

        if (leveragedPosDai > 0) {
            storageT.transferLinkToAggregator(sender, pairIndex, leveragedPosDai);
        }

        uint256 orderId = _getPriceNftOrder(
            isOpenLimit,
            trader,
            pairIndex,
            index,
            isOpenLimit ? IGNSTradingCallbacks.TradeType.LIMIT : IGNSTradingCallbacks.TradeType.MARKET,
            orderType,
            leveragedPosDai
        );

        IGNSTradingStorage.PendingNftOrder memory pendingNftOrder;
        pendingNftOrder.nftHolder = sender;
        pendingNftOrder.nftId = 0;
        pendingNftOrder.trader = trader;
        pendingNftOrder.pairIndex = pairIndex;
        pendingNftOrder.index = index;
        pendingNftOrder.orderType = orderType;

        storageT.storePendingNftOrder(pendingNftOrder, orderId);
        oracleRewards.storeTrigger(triggeredLimitId);

        emit NftOrderInitiated(orderId, trader, pairIndex, byPassesLinkCost);
    }

    // Market timeout
    function openTradeMarketTimeout(uint256 _order) external notContract notDone {
        address sender = _msgSender();

        IGNSTradingStorage.PendingMarketOrder memory o = storageT.reqID_pendingMarketOrder(_order);
        IGNSTradingStorage.Trade memory t = o.trade;

        require(o.block > 0 && block.number >= o.block + marketOrdersTimeout, "WAIT_TIMEOUT");
        require(t.trader == sender, "NOT_YOUR_ORDER");
        require(t.leverage > 0, "WRONG_MARKET_ORDER_TYPE");

        storageT.unregisterPendingMarketOrder(_order, true);
        storageT.transferDai(address(storageT), sender, t.positionSizeDai);

        emit ChainlinkCallbackTimeout(_order, o);
    }

    function closeTradeMarketTimeout(uint256 _order) external notContract notDone {
        address sender = _msgSender();

        IGNSTradingStorage.PendingMarketOrder memory o = storageT.reqID_pendingMarketOrder(_order);
        IGNSTradingStorage.Trade memory t = o.trade;

        require(o.block > 0 && block.number >= o.block + marketOrdersTimeout, "WAIT_TIMEOUT");
        require(t.trader == sender, "NOT_YOUR_ORDER");
        require(t.leverage == 0, "WRONG_MARKET_ORDER_TYPE");

        storageT.unregisterPendingMarketOrder(_order, false);

        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSignature("closeTradeMarket(uint256,uint256)", t.pairIndex, t.index)
        );

        if (!success) {
            emit CouldNotCloseTrade(sender, t.pairIndex, t.index);
        }

        emit ChainlinkCallbackTimeout(_order, o);
    }

    // Helpers (private)
    function _checkNoPendingTrigger(
        address trader,
        uint256 pairIndex,
        uint256 index,
        IGNSTradingStorage.LimitOrder orderType
    ) private view returns (IGNSOracleRewards.TriggeredLimitId memory triggeredLimitId) {
        triggeredLimitId = IGNSOracleRewards.TriggeredLimitId(trader, pairIndex, index, orderType);
        require(
            !oracleRewards.triggered(triggeredLimitId) || oracleRewards.timedOut(triggeredLimitId),
            "PENDING_TRIGGER"
        );
    }

    function _pairMaxLeverage(IGNSPairsStorage pairsStored, uint256 pairIndex) private view returns (uint256) {
        uint256 max = IGNSTradingCallbacks(storageT.callbacks()).pairMaxLeverage(pairIndex);
        return max > 0 ? max : pairsStored.pairMaxLeverage(pairIndex);
    }

    function _getPriceNftOrder(
        bool isOpenLimit,
        address trader,
        uint256 pairIndex,
        uint256 index,
        IGNSTradingCallbacks.TradeType tradeType,
        IGNSTradingStorage.LimitOrder orderType,
        uint256 leveragedPosDai
    ) private returns (uint256 orderId) {
        IGNSTradingCallbacks.LastUpdated memory lastUpdated = IGNSTradingCallbacks(storageT.callbacks())
            .getTradeLastUpdated(trader, pairIndex, index, tradeType);

        IGNSPriceAggregator aggregator = storageT.priceAggregator();

        orderId = aggregator.getPrice(
            pairIndex,
            isOpenLimit ? IGNSPriceAggregator.OrderType.LIMIT_OPEN : IGNSPriceAggregator.OrderType.LIMIT_CLOSE,
            leveragedPosDai,
            isOpenLimit ? lastUpdated.limit : orderType == IGNSTradingStorage.LimitOrder.SL
                ? lastUpdated.sl
                : orderType == IGNSTradingStorage.LimitOrder.TP
                ? lastUpdated.tp
                : lastUpdated.created
        );
    }
}

