// SPDX-License-Identifier: MIT
import "./StorageInterfaceV5.sol";
import "./GNSPairInfosInterfaceV6.sol";
import "./GNSReferralsInterfaceV6_2.sol";
import "./GNSBorrowingFeesInterfaceV6_4.sol";
import "./Delegatable.sol";
import "./ChainUtils.sol";
import "./TradeUtils.sol";
import "./PackingUtils.sol";

pragma solidity 0.8.17;

contract GNSTradingV6_4 is Delegatable {
    using TradeUtils for address;
    using PackingUtils for uint256;

    // Contracts (constant)
    StorageInterfaceV5 public immutable storageT;
    NftRewardsInterfaceV6_3_1 public immutable nftRewards;
    GNSPairInfosInterfaceV6 public immutable pairInfos;
    GNSReferralsInterfaceV6_2 public immutable referrals;
    GNSBorrowingFeesInterfaceV6_4 public immutable borrowingFees;

    // Params (constant)
    uint constant PRECISION = 1e10;
    uint constant MAX_SL_P = 75; // -75% PNL

    // Params (adjustable)
    uint public maxPosDai; // 1e18 (eg. 75000 * 1e18)
    uint public marketOrdersTimeout; // block (eg. 30)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    // Events
    event Done(bool done);
    event Paused(bool paused);

    event NumberUpdated(string name, uint value);

    event MarketOrderInitiated(uint indexed orderId, address indexed trader, uint indexed pairIndex, bool open);

    event OpenLimitPlaced(address indexed trader, uint indexed pairIndex, uint index);
    event OpenLimitUpdated(
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        uint newPrice,
        uint newTp,
        uint newSl,
        uint maxSlippageP
    );
    event OpenLimitCanceled(address indexed trader, uint indexed pairIndex, uint index);

    event TpUpdated(address indexed trader, uint indexed pairIndex, uint index, uint newTp);
    event SlUpdated(address indexed trader, uint indexed pairIndex, uint index, uint newSl);

    event NftOrderInitiated(uint orderId, address indexed nftHolder, address indexed trader, uint indexed pairIndex);
    event NftOrderSameBlock(address indexed nftHolder, address indexed trader, uint indexed pairIndex);

    event ChainlinkCallbackTimeout(uint indexed orderId, StorageInterfaceV5.PendingMarketOrder order);
    event CouldNotCloseTrade(address indexed trader, uint indexed pairIndex, uint index);

    constructor(
        StorageInterfaceV5 _storageT,
        NftRewardsInterfaceV6_3_1 _nftRewards,
        GNSPairInfosInterfaceV6 _pairInfos,
        GNSReferralsInterfaceV6_2 _referrals,
        GNSBorrowingFeesInterfaceV6_4 _borrowingFees,
        uint _maxPosDai,
        uint _marketOrdersTimeout
    ) {
        require(
            address(_storageT) != address(0) &&
                address(_nftRewards) != address(0) &&
                address(_pairInfos) != address(0) &&
                address(_referrals) != address(0) &&
                address(_borrowingFees) != address(0) &&
                _maxPosDai > 0 &&
                _marketOrdersTimeout > 0,
            "WRONG_PARAMS"
        );

        storageT = _storageT;
        nftRewards = _nftRewards;
        pairInfos = _pairInfos;
        referrals = _referrals;
        borrowingFees = _borrowingFees;

        maxPosDai = _maxPosDai;
        marketOrdersTimeout = _marketOrdersTimeout;
    }

    // Modifiers
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

    // Saving code size by calling these functions inside modifiers
    function isGov() private view {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
    }

    function isNotContract() private view {
        require(tx.origin == msg.sender);
    }

    function isNotDone() private view {
        require(!isDone, "DONE");
    }

    // Manage params
    function setMaxPosDai(uint value) external onlyGov {
        require(value > 0, "VALUE_0");
        maxPosDai = value;
        emit NumberUpdated("maxPosDai", value);
    }

    function setMarketOrdersTimeout(uint value) external onlyGov {
        require(value > 0, "VALUE_0");
        marketOrdersTimeout = value;
        emit NumberUpdated("marketOrdersTimeout", value);
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
        StorageInterfaceV5.Trade memory t,
        NftRewardsInterfaceV6_3_1.OpenLimitOrderType orderType, // LEGACY => market
        uint spreadReductionId,
        uint slippageP, // 1e10 (%)
        address referrer
    ) external notContract notDone {
        require(!isPaused, "PAUSED");
        require(t.openPrice * slippageP < type(uint256).max, "OVERFLOW");
        require(t.openPrice > 0, "PRICE_ZERO");

        AggregatorInterfaceV6_4 aggregator = storageT.priceAggregator();
        PairsStorageInterfaceV6 pairsStored = aggregator.pairsStorage();

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
        require(t.positionSizeDai * t.leverage >= pairsStored.pairMinLevPosDai(t.pairIndex), "BELOW_MIN_POS");

        require(
            t.leverage > 0 &&
                t.leverage >= pairsStored.pairMinLeverage(t.pairIndex) &&
                t.leverage <= pairMaxLeverage(pairsStored, t.pairIndex),
            "LEVERAGE_INCORRECT"
        );

        require(
            spreadReductionId == 0 || storageT.nfts(spreadReductionId - 1).balanceOf(sender) > 0,
            "NO_CORRESPONDING_NFT_SPREAD_REDUCTION"
        );

        require(t.tp == 0 || (t.buy ? t.tp > t.openPrice : t.tp < t.openPrice), "WRONG_TP");
        require(t.sl == 0 || (t.buy ? t.sl < t.openPrice : t.sl > t.openPrice), "WRONG_SL");

        (uint priceImpactP, ) = pairInfos.getTradePriceImpact(0, t.pairIndex, t.buy, t.positionSizeDai * t.leverage);
        require(priceImpactP * t.leverage <= pairInfos.maxNegativePnlOnOpenP(), "PRICE_IMPACT_TOO_HIGH");

        storageT.transferDai(sender, address(storageT), t.positionSizeDai);

        if (orderType != NftRewardsInterfaceV6_3_1.OpenLimitOrderType.LEGACY) {
            uint index = storageT.firstEmptyOpenLimitIndex(sender, t.pairIndex);

            storageT.storeOpenLimitOrder(
                StorageInterfaceV5.OpenLimitOrder(
                    sender,
                    t.pairIndex,
                    index,
                    t.positionSizeDai,
                    spreadReductionId > 0 ? storageT.spreadReductionsP(spreadReductionId - 1) : 0,
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

            nftRewards.setOpenLimitOrderType(sender, t.pairIndex, index, orderType);

            address c = storageT.callbacks();
            c.setTradeLastUpdated(
                sender,
                t.pairIndex,
                index,
                TradingCallbacksV6_4.TradeType.LIMIT,
                ChainUtils.getBlockNumber()
            );
            c.setTradeData(sender, t.pairIndex, index, TradingCallbacksV6_4.TradeType.LIMIT, slippageP);

            emit OpenLimitPlaced(sender, t.pairIndex, index);
        } else {
            uint orderId = aggregator.getPrice(
                t.pairIndex,
                AggregatorInterfaceV6_4.OrderType.MARKET_OPEN,
                t.positionSizeDai * t.leverage,
                ChainUtils.getBlockNumber()
            );

            storageT.storePendingMarketOrder(
                StorageInterfaceV5.PendingMarketOrder(
                    StorageInterfaceV5.Trade(
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
                    spreadReductionId > 0 ? storageT.spreadReductionsP(spreadReductionId - 1) : 0,
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
    function closeTradeMarket(uint pairIndex, uint index) external notContract notDone {
        address sender = _msgSender();

        StorageInterfaceV5.Trade memory t = storageT.openTrades(sender, pairIndex, index);
        StorageInterfaceV5.TradeInfo memory i = storageT.openTradesInfo(sender, pairIndex, index);

        require(storageT.pendingOrderIdsCount(sender) < storageT.maxPendingMarketOrders(), "MAX_PENDING_ORDERS");
        require(!i.beingMarketClosed, "ALREADY_BEING_CLOSED");
        require(t.leverage > 0, "NO_TRADE");

        uint orderId = storageT.priceAggregator().getPrice(
            pairIndex,
            AggregatorInterfaceV6_4.OrderType.MARKET_CLOSE,
            (t.initialPosToken * i.tokenPriceDai * t.leverage) / PRECISION,
            ChainUtils.getBlockNumber()
        );

        storageT.storePendingMarketOrder(
            StorageInterfaceV5.PendingMarketOrder(
                StorageInterfaceV5.Trade(sender, pairIndex, index, 0, 0, 0, false, 0, 0, 0),
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
        uint pairIndex,
        uint index,
        uint price, // PRECISION
        uint tp,
        uint sl,
        uint maxSlippageP
    ) external notContract notDone {
        require(price > 0, "PRICE_ZERO");

        address sender = _msgSender();
        require(storageT.hasOpenLimitOrder(sender, pairIndex, index), "NO_LIMIT");

        StorageInterfaceV5.OpenLimitOrder memory o = storageT.getOpenLimitOrder(sender, pairIndex, index);

        require(tp == 0 || (o.buy ? tp > price : tp < price), "WRONG_TP");
        require(sl == 0 || (o.buy ? sl < price : sl > price), "WRONG_SL");

        require(price * maxSlippageP < type(uint256).max, "OVERFLOW");

        checkNoPendingTrigger(sender, pairIndex, index, StorageInterfaceV5.LimitOrder.OPEN);

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
            TradingCallbacksV6_4.TradeType.LIMIT,
            ChainUtils.getBlockNumber()
        );
        c.setTradeData(sender, pairIndex, index, TradingCallbacksV6_4.TradeType.LIMIT, maxSlippageP);

        emit OpenLimitUpdated(sender, pairIndex, index, price, tp, sl, maxSlippageP);
    }

    function cancelOpenLimitOrder(uint pairIndex, uint index) external notContract notDone {
        address sender = _msgSender();
        require(storageT.hasOpenLimitOrder(sender, pairIndex, index), "NO_LIMIT");

        StorageInterfaceV5.OpenLimitOrder memory o = storageT.getOpenLimitOrder(sender, pairIndex, index);

        checkNoPendingTrigger(sender, pairIndex, index, StorageInterfaceV5.LimitOrder.OPEN);

        storageT.unregisterOpenLimitOrder(sender, pairIndex, index);
        storageT.transferDai(address(storageT), sender, o.positionSize);

        emit OpenLimitCanceled(sender, pairIndex, index);
    }

    // Manage limit order (TP/SL)
    function updateTp(uint pairIndex, uint index, uint newTp) external notContract notDone {
        address sender = _msgSender();

        checkNoPendingTrigger(sender, pairIndex, index, StorageInterfaceV5.LimitOrder.TP);

        StorageInterfaceV5.Trade memory t = storageT.openTrades(sender, pairIndex, index);
        require(t.leverage > 0, "NO_TRADE");

        storageT.updateTp(sender, pairIndex, index, newTp);
        storageT.callbacks().setTpLastUpdated(
            sender,
            pairIndex,
            index,
            TradingCallbacksV6_4.TradeType.MARKET,
            ChainUtils.getBlockNumber()
        );

        emit TpUpdated(sender, pairIndex, index, newTp);
    }

    function updateSl(uint pairIndex, uint index, uint newSl) external notContract notDone {
        address sender = _msgSender();

        checkNoPendingTrigger(sender, pairIndex, index, StorageInterfaceV5.LimitOrder.SL);

        StorageInterfaceV5.Trade memory t = storageT.openTrades(sender, pairIndex, index);
        require(t.leverage > 0, "NO_TRADE");

        uint maxSlDist = (t.openPrice * MAX_SL_P) / 100 / t.leverage;

        require(
            newSl == 0 || (t.buy ? newSl >= t.openPrice - maxSlDist : newSl <= t.openPrice + maxSlDist),
            "SL_TOO_BIG"
        );

        storageT.updateSl(sender, pairIndex, index, newSl);
        storageT.callbacks().setSlLastUpdated(
            sender,
            pairIndex,
            index,
            TradingCallbacksV6_4.TradeType.MARKET,
            ChainUtils.getBlockNumber()
        );

        emit SlUpdated(sender, pairIndex, index, newSl);
    }

    // Execute limit order
    function executeNftOrder(uint256 packed) external notContract notDone {
        (uint _orderType, address trader, uint pairIndex, uint index, uint nftId, uint nftType) = packed
            .unpackExecuteNftOrder();
        StorageInterfaceV5.LimitOrder orderType = StorageInterfaceV5.LimitOrder(_orderType);
        address sender = _msgSender();

        require(nftType >= 1 && nftType <= 5, "WRONG_NFT_TYPE");
        require(storageT.nfts(nftType - 1).ownerOf(nftId) == sender, "NO_NFT");

        require(block.number >= storageT.nftLastSuccess(nftId) + storageT.nftSuccessTimelock(), "SUCCESS_TIMELOCK");

        bool isOpenLimit = orderType == StorageInterfaceV5.LimitOrder.OPEN;
        TradingCallbacksV6_4.TradeType tradeType = isOpenLimit
            ? TradingCallbacksV6_4.TradeType.LIMIT
            : TradingCallbacksV6_4.TradeType.MARKET;

        require(
            canExecute(orderType, TradingCallbacksV6_4.SimplifiedTradeId(trader, pairIndex, index, tradeType)),
            "IN_TIMEOUT"
        );

        handleBotInUse(sender, nftId, trader, pairIndex, index);

        StorageInterfaceV5.Trade memory t;

        if (isOpenLimit) {
            require(storageT.hasOpenLimitOrder(trader, pairIndex, index), "NO_LIMIT");
        } else {
            t = storageT.openTrades(trader, pairIndex, index);

            require(t.leverage > 0, "NO_TRADE");

            if (orderType == StorageInterfaceV5.LimitOrder.LIQ) {
                uint liqPrice = borrowingFees.getTradeLiquidationPrice(
                    GNSBorrowingFeesInterfaceV6_4.LiqPriceInput(
                        t.trader,
                        t.pairIndex,
                        t.index,
                        t.openPrice,
                        t.buy,
                        (t.initialPosToken * storageT.openTradesInfo(t.trader, t.pairIndex, t.index).tokenPriceDai) /
                            PRECISION,
                        t.leverage
                    )
                );

                require(t.sl == 0 || (t.buy ? liqPrice > t.sl : liqPrice < t.sl), "HAS_SL");
            } else {
                require(orderType != StorageInterfaceV5.LimitOrder.SL || t.sl > 0, "NO_SL");
                require(orderType != StorageInterfaceV5.LimitOrder.TP || t.tp > 0, "NO_TP");
            }
        }

        NftRewardsInterfaceV6_3_1.TriggeredLimitId memory triggeredLimitId = NftRewardsInterfaceV6_3_1.TriggeredLimitId(
            trader,
            pairIndex,
            index,
            orderType
        );

        if (!nftRewards.triggered(triggeredLimitId) || nftRewards.timedOut(triggeredLimitId)) {
            uint leveragedPosDai;

            if (isOpenLimit) {
                StorageInterfaceV5.OpenLimitOrder memory l = storageT.getOpenLimitOrder(trader, pairIndex, index);

                leveragedPosDai = l.positionSize * l.leverage;
                (uint priceImpactP, ) = pairInfos.getTradePriceImpact(0, l.pairIndex, l.buy, leveragedPosDai);

                require(priceImpactP * l.leverage <= pairInfos.maxNegativePnlOnOpenP(), "PRICE_IMPACT_TOO_HIGH");
            } else {
                leveragedPosDai =
                    (t.initialPosToken * storageT.openTradesInfo(trader, pairIndex, index).tokenPriceDai * t.leverage) /
                    PRECISION;
            }

            storageT.transferLinkToAggregator(sender, pairIndex, leveragedPosDai);

            (uint orderId, uint linkFee) = getPriceNftOrder(
                isOpenLimit,
                trader,
                pairIndex,
                index,
                tradeType,
                orderType,
                leveragedPosDai
            );

            StorageInterfaceV5.PendingNftOrder memory pendingNftOrder;
            pendingNftOrder.nftHolder = sender;
            pendingNftOrder.nftId = nftId;
            pendingNftOrder.trader = trader;
            pendingNftOrder.pairIndex = pairIndex;
            pendingNftOrder.index = index;
            pendingNftOrder.orderType = orderType;

            storageT.storePendingNftOrder(pendingNftOrder, orderId);
            nftRewards.storeFirstToTrigger(triggeredLimitId, sender, linkFee);

            emit NftOrderInitiated(orderId, sender, trader, pairIndex);
        } else {
            nftRewards.storeTriggerSameBlock(triggeredLimitId, sender);

            emit NftOrderSameBlock(sender, trader, pairIndex);
        }
    }

    // Market timeout
    function openTradeMarketTimeout(uint _order) external notContract notDone {
        address sender = _msgSender();

        StorageInterfaceV5.PendingMarketOrder memory o = storageT.reqID_pendingMarketOrder(_order);
        StorageInterfaceV5.Trade memory t = o.trade;

        require(o.block > 0 && block.number >= o.block + marketOrdersTimeout, "WAIT_TIMEOUT");
        require(t.trader == sender, "NOT_YOUR_ORDER");
        require(t.leverage > 0, "WRONG_MARKET_ORDER_TYPE");

        storageT.unregisterPendingMarketOrder(_order, true);
        storageT.transferDai(address(storageT), sender, t.positionSizeDai);

        emit ChainlinkCallbackTimeout(_order, o);
    }

    function closeTradeMarketTimeout(uint _order) external notContract notDone {
        address sender = _msgSender();

        StorageInterfaceV5.PendingMarketOrder memory o = storageT.reqID_pendingMarketOrder(_order);
        StorageInterfaceV5.Trade memory t = o.trade;

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

    // Helpers
    function checkNoPendingTrigger(
        address trader,
        uint pairIndex,
        uint index,
        StorageInterfaceV5.LimitOrder orderType
    ) private view {
        NftRewardsInterfaceV6_3_1.TriggeredLimitId memory triggeredLimitId = NftRewardsInterfaceV6_3_1.TriggeredLimitId(
            trader,
            pairIndex,
            index,
            orderType
        );
        require(!nftRewards.triggered(triggeredLimitId) || nftRewards.timedOut(triggeredLimitId), "PENDING_TRIGGER");
    }

    function canExecute(
        StorageInterfaceV5.LimitOrder orderType,
        TradingCallbacksV6_4.SimplifiedTradeId memory id
    ) private view returns (bool) {
        if (orderType == StorageInterfaceV5.LimitOrder.LIQ) return true;

        uint b = ChainUtils.getBlockNumber();
        address cb = storageT.callbacks();

        if (orderType == StorageInterfaceV5.LimitOrder.TP) return !cb.isTpInTimeout(id, b);
        if (orderType == StorageInterfaceV5.LimitOrder.SL) return !cb.isSlInTimeout(id, b);

        return !cb.isLimitInTimeout(id, b);
    }

    function pairMaxLeverage(PairsStorageInterfaceV6 pairsStored, uint pairIndex) private view returns (uint) {
        uint max = TradingCallbacksV6_4(storageT.callbacks()).pairMaxLeverage(pairIndex);
        return max > 0 ? max : pairsStored.pairMaxLeverage(pairIndex);
    }

    function handleBotInUse(address sender, uint nftId, address trader, uint pairIndex, uint index) private {
        (bytes32 nftHash, bytes32 botHash) = nftRewards.getNftBotHashes(
            block.number,
            sender,
            nftId,
            trader,
            pairIndex,
            index
        );
        require(!nftRewards.nftBotInUse(nftHash, botHash), "BOT_IN_USE");

        nftRewards.setNftBotInUse(nftHash, botHash);
    }

    function getPriceNftOrder(
        bool isOpenLimit,
        address trader,
        uint pairIndex,
        uint index,
        TradingCallbacksV6_4.TradeType tradeType,
        StorageInterfaceV5.LimitOrder orderType,
        uint leveragedPosDai
    ) private returns (uint orderId, uint linkFee) {
        TradingCallbacksV6_4.LastUpdated memory lastUpdated = TradingCallbacksV6_4(storageT.callbacks())
            .tradeLastUpdated(trader, pairIndex, index, tradeType);

        AggregatorInterfaceV6_4 aggregator = storageT.priceAggregator();

        orderId = aggregator.getPrice(
            pairIndex,
            isOpenLimit ? AggregatorInterfaceV6_4.OrderType.LIMIT_OPEN : AggregatorInterfaceV6_4.OrderType.LIMIT_CLOSE,
            leveragedPosDai,
            isOpenLimit ? lastUpdated.limit : orderType == StorageInterfaceV5.LimitOrder.SL
                ? lastUpdated.sl
                : orderType == StorageInterfaceV5.LimitOrder.TP
                ? lastUpdated.tp
                : lastUpdated.created
        );

        linkFee = aggregator.linkFee(pairIndex, leveragedPosDai);
    }
}

