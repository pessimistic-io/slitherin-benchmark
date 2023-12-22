// File: contracts\interfaces\UniswapRouterInterfaceV5.sol
// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;
import "./UniswapRouterInterfaceV5.sol";
import "./TokenInterfaceV5.sol";
import "./NftInterfaceV5.sol";
import "./VaultInterfaceV5.sol";
import "./PairsStorageInterfaceV6.sol";
import "./StorageInterfaceV5.sol";
import "./MMTPairInfosInterfaceV6.sol";
import "./MMTReferralsInterfaceV6_2.sol";
import "./NftRewardsInterfaceV6.sol";
import "./IWhitelist.sol";
import "./Delegatable.sol";

contract MTTTrading is Delegatable {
    // Contracts (constant)
    StorageInterfaceV5 public immutable storageT;
    NftRewardsInterfaceV6 public immutable nftRewards;
    MMTPairInfosInterfaceV6 public immutable pairInfos;
    MMTReferralsInterfaceV6_2 public immutable referrals;
    IWhitelist public whitelist;

    // Params (constant)
    uint256 constant PRECISION = 1e10;
    uint256 constant MAX_SL_P = 75; // -75% PNL

    // Params (adjustable)
    uint256 public maxPosDai; // 1e18 (eg. 75000 * 1e18)
    uint256 public limitOrdersTimelock; // block (eg. 30)
    uint256 public marketOrdersTimeout; // block (eg. 30)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    // Events
    event Done(bool done);
    event Paused(bool paused);

    event NumberUpdated(string name, uint256 value);

    event MarketOrderInitiated(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        bool open
    );

    event OpenLimitPlaced(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index
    );
    event OpenLimitUpdated(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 newPrice,
        uint256 newTp,
        uint256 newSl
    );
    event OpenLimitCanceled(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index
    );

    event TpUpdated(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 newTp
    );
    event SlUpdated(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 newSl
    );
    event SlUpdateInitiated(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 newSl
    );

    event NftOrderInitiated(
        uint256 orderId,
        address indexed nftHolder,
        address indexed trader,
        uint256 indexed pairIndex
    );
    event NftOrderSameBlock(
        address indexed nftHolder,
        address indexed trader,
        uint256 indexed pairIndex
    );

    event ChainlinkCallbackTimeout(
        uint256 indexed orderId,
        StorageInterfaceV5.PendingMarketOrder order
    );
    event CouldNotCloseTrade(
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index
    );

    constructor(
        StorageInterfaceV5 _storageT,
        NftRewardsInterfaceV6 _nftRewards,
        MMTPairInfosInterfaceV6 _pairInfos,
        MMTReferralsInterfaceV6_2 _referrals,
        uint256 _maxPosDai,
        uint256 _limitOrdersTimelock,
        uint256 _marketOrdersTimeout
    ) {
        require(
            address(_storageT) != address(0) &&
                address(_nftRewards) != address(0) &&
                address(_pairInfos) != address(0) &&
                address(_referrals) != address(0) &&
                _maxPosDai > 0 &&
                _limitOrdersTimelock > 0 &&
                _marketOrdersTimeout > 0,
            "WRONG_PARAMS"
        );

        storageT = _storageT;
        nftRewards = _nftRewards;
        pairInfos = _pairInfos;
        referrals = _referrals;

        maxPosDai = _maxPosDai;
        limitOrdersTimelock = _limitOrdersTimelock;
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

    modifier checkWhitelist() {
        require(
            address(whitelist) == address(0) ||
                whitelist.isWhitelists(msg.sender),
            "NOT_IN_WHITELIST"
        );
        _;
    }

    // Manage params
    function setMaxPosDai(uint256 value) external onlyGov {
        require(value > 0, "VALUE_0");
        maxPosDai = value;

        emit NumberUpdated("maxPosDai", value);
    }

    function setLimitOrdersTimelock(uint256 value) external onlyGov {
        require(value > 0, "VALUE_0");
        limitOrdersTimelock = value;

        emit NumberUpdated("limitOrdersTimelock", value);
    }

    function setMarketOrdersTimeout(uint256 value) external onlyGov {
        require(value > 0, "VALUE_0");
        marketOrdersTimeout = value;

        emit NumberUpdated("marketOrdersTimeout", value);
    }

    function setWhitelistContract(IWhitelist whitelistContract)
        external
        onlyGov
    {
        whitelist = whitelistContract;
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
        NftRewardsInterfaceV6.OpenLimitOrderType orderType, // LEGACY => market
        uint256 spreadReductionId,
        uint256 slippageP, // for market orders only
        address referrer
    ) external notContract notDone checkWhitelist {
        require(!isPaused, "PAUSED");

        AggregatorInterfaceV6 aggregator = storageT.priceAggregator();
        PairsStorageInterfaceV6 pairsStored = aggregator.pairsStorage();

        address sender = _msgSender();

        require(
            storageT.openTradesCount(sender, t.pairIndex) +
                storageT.pendingMarketOpenCount(sender, t.pairIndex) +
                storageT.openLimitOrdersCount(sender, t.pairIndex) <
                storageT.maxTradesPerPair(),
            "MAX_TRADES_PER_PAIR"
        );

        require(
            storageT.pendingOrderIdsCount(sender) <
                storageT.maxPendingMarketOrders(),
            "MAX_PENDING_ORDERS"
        );

        require(t.positionSizeDai <= maxPosDai, "ABOVE_MAX_POS");
        require(
            t.positionSizeDai * t.leverage >=
                pairsStored.pairMinLevPosDai(t.pairIndex),
            "BELOW_MIN_POS"
        );

        require(
            t.leverage > 0 &&
                t.leverage >= pairsStored.pairMinLeverage(t.pairIndex) &&
                t.leverage <= pairsStored.pairMaxLeverage(t.pairIndex),
            "LEVERAGE_INCORRECT"
        );

        require(
            spreadReductionId == 0 ||
                storageT.nfts(spreadReductionId - 1).balanceOf(sender) > 0,
            "NO_CORRESPONDING_NFT_SPREAD_REDUCTION"
        );

        require(
            t.tp == 0 || (t.buy ? t.tp > t.openPrice : t.tp < t.openPrice),
            "WRONG_TP"
        );

        require(
            t.sl == 0 || (t.buy ? t.sl < t.openPrice : t.sl > t.openPrice),
            "WRONG_SL"
        );

        (uint256 priceImpactP, ) = pairInfos.getTradePriceImpact(
            0,
            t.pairIndex,
            t.buy,
            t.positionSizeDai * t.leverage
        );

        require(
            priceImpactP * t.leverage <= pairInfos.maxNegativePnlOnOpenP(),
            "PRICE_IMPACT_TOO_HIGH"
        );

        storageT.transferDai(sender, address(storageT), t.positionSizeDai);

        //thangtest
        //referrals.registerPotentialReferrer(sender, referrer);

        if (orderType != NftRewardsInterfaceV6.OpenLimitOrderType.LEGACY) {
            uint256 index = storageT.firstEmptyOpenLimitIndex(
                sender,
                t.pairIndex
            );

            storageT.storeOpenLimitOrder(
                StorageInterfaceV5.OpenLimitOrder(
                    sender,
                    t.pairIndex,
                    index,
                    t.positionSizeDai,
                    spreadReductionId > 0
                        ? storageT.spreadReductionsP(spreadReductionId - 1)
                        : 0,
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

            nftRewards.setOpenLimitOrderType(
                sender,
                t.pairIndex,
                index,
                orderType
            );

            emit OpenLimitPlaced(sender, t.pairIndex, index);
        } else {
            uint256 orderId = aggregator.getPrice(
                t.pairIndex,
                AggregatorInterfaceV6.OrderType.MARKET_OPEN,
                t.positionSizeDai * t.leverage
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
                    spreadReductionId > 0
                        ? storageT.spreadReductionsP(spreadReductionId - 1)
                        : 0,
                    0
                ),
                orderId,
                true
            );

            aggregator.emptyNodeFulFill(
                t.pairIndex,
                orderId,
                AggregatorInterfaceV6.OrderType.MARKET_OPEN
            );

            emit MarketOrderInitiated(orderId, sender, t.pairIndex, true);
        }

        //thangtest move up function
        referrals.registerPotentialReferrer(sender, referrer);
    }

    // Close trade (MARKET)
    function closeTradeMarket(uint256 pairIndex, uint256 index)
        external
        notContract
        notDone
    {
        address sender = _msgSender();

        StorageInterfaceV5.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        StorageInterfaceV5.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );

        require(
            storageT.pendingOrderIdsCount(sender) <
                storageT.maxPendingMarketOrders(),
            "MAX_PENDING_ORDERS"
        );

        require(!i.beingMarketClosed, "ALREADY_BEING_CLOSED");
        require(t.leverage > 0, "NO_TRADE");

        uint256 orderId = storageT.priceAggregator().getPrice(
            pairIndex,
            AggregatorInterfaceV6.OrderType.MARKET_CLOSE,
            (t.initialPosToken * i.tokenPriceDai * t.leverage) / PRECISION
        );

        storageT.storePendingMarketOrder(
            StorageInterfaceV5.PendingMarketOrder(
                StorageInterfaceV5.Trade(
                    sender,
                    pairIndex,
                    index,
                    0,
                    0,
                    0,
                    false,
                    0,
                    0,
                    0
                ),
                0,
                0,
                0,
                0,
                0
            ),
            orderId,
            false
        );

        storageT.priceAggregator().emptyNodeFulFill(
            pairIndex,
            orderId,
            AggregatorInterfaceV6.OrderType.MARKET_CLOSE
        );

        emit MarketOrderInitiated(orderId, sender, pairIndex, false);
    }

    // Manage limit order (OPEN)
    function updateOpenLimitOrder(
        uint256 pairIndex,
        uint256 index,
        uint256 price, // PRECISION
        uint256 tp,
        uint256 sl
    ) external notContract notDone {
        address sender = _msgSender();

        require(
            storageT.hasOpenLimitOrder(sender, pairIndex, index),
            "NO_LIMIT"
        );

        StorageInterfaceV5.OpenLimitOrder memory o = storageT.getOpenLimitOrder(
            sender,
            pairIndex,
            index
        );

        require(
            block.number - o.block >= limitOrdersTimelock,
            "LIMIT_TIMELOCK"
        );

        require(tp == 0 || (o.buy ? tp > price : tp < price), "WRONG_TP");

        require(sl == 0 || (o.buy ? sl < price : sl > price), "WRONG_SL");

        o.minPrice = price;
        o.maxPrice = price;

        o.tp = tp;
        o.sl = sl;

        storageT.updateOpenLimitOrder(o);

        emit OpenLimitUpdated(sender, pairIndex, index, price, tp, sl);
    }

    function cancelOpenLimitOrder(uint256 pairIndex, uint256 index)
        external
        notContract
        notDone
    {
        address sender = _msgSender();

        require(
            storageT.hasOpenLimitOrder(sender, pairIndex, index),
            "NO_LIMIT"
        );

        StorageInterfaceV5.OpenLimitOrder memory o = storageT.getOpenLimitOrder(
            sender,
            pairIndex,
            index
        );

        require(
            block.number - o.block >= limitOrdersTimelock,
            "LIMIT_TIMELOCK"
        );

        storageT.unregisterOpenLimitOrder(sender, pairIndex, index);
        storageT.transferDai(address(storageT), sender, o.positionSize);

        emit OpenLimitCanceled(sender, pairIndex, index);
    }

    // Manage limit order (TP/SL)
    function updateTp(
        uint256 pairIndex,
        uint256 index,
        uint256 newTp
    ) external notContract notDone {
        address sender = _msgSender();

        StorageInterfaceV5.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        StorageInterfaceV5.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );

        require(t.leverage > 0, "NO_TRADE");
        require(
            block.number - i.tpLastUpdated >= limitOrdersTimelock,
            "LIMIT_TIMELOCK"
        );

        storageT.updateTp(sender, pairIndex, index, newTp);

        emit TpUpdated(sender, pairIndex, index, newTp);
    }

    function updateSl(
        uint256 pairIndex,
        uint256 index,
        uint256 newSl
    ) external notContract notDone {
        address sender = _msgSender();

        StorageInterfaceV5.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        StorageInterfaceV5.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );

        require(t.leverage > 0, "NO_TRADE");

        uint256 maxSlDist = (t.openPrice * MAX_SL_P) / 100 / t.leverage;

        require(
            newSl == 0 ||
                (
                    t.buy
                        ? newSl >= t.openPrice - maxSlDist
                        : newSl <= t.openPrice + maxSlDist
                ),
            "SL_TOO_BIG"
        );

        require(
            block.number - i.slLastUpdated >= limitOrdersTimelock,
            "LIMIT_TIMELOCK"
        );

        AggregatorInterfaceV6 aggregator = storageT.priceAggregator();

        if (
            newSl == 0 ||
            !aggregator.pairsStorage().guaranteedSlEnabled(pairIndex)
        ) {
            storageT.updateSl(sender, pairIndex, index, newSl);

            emit SlUpdated(sender, pairIndex, index, newSl);
        } else {
            uint256 orderId = aggregator.getPrice(
                pairIndex,
                AggregatorInterfaceV6.OrderType.UPDATE_SL,
                (t.initialPosToken * i.tokenPriceDai * t.leverage) / PRECISION
            );

            aggregator.storePendingSlOrder(
                orderId,
                AggregatorInterfaceV6.PendingSl(
                    sender,
                    pairIndex,
                    index,
                    t.openPrice,
                    t.buy,
                    newSl
                )
            );
            aggregator.emptyNodeFulFill(
                pairIndex,
                orderId,
                AggregatorInterfaceV6.OrderType.UPDATE_SL
            );

            emit SlUpdateInitiated(orderId, sender, pairIndex, index, newSl);
        }
    }

    // Execute Order B yGPT3-Bot
    function executeOrderByGPT3Bot(
        StorageInterfaceV5.LimitOrder orderType,
        address trader,
        uint256 pairIndex,
        uint256 index,
        uint256 nftId,
        uint256 nftType
    ) external notContract notDone checkWhitelist {
        address sender = _msgSender();

        require(nftType >= 1 && nftType <= 5, "WRONG_NFT_TYPE");
        require(storageT.nfts(nftType - 1).ownerOf(nftId) == sender, "NO_NFT");

        require(
            block.number >=
                storageT.nftLastSuccess(nftId) + storageT.nftSuccessTimelock(),
            "SUCCESS_TIMELOCK"
        );

        StorageInterfaceV5.Trade memory t;

        if (orderType == StorageInterfaceV5.LimitOrder.OPEN) {
            require(
                storageT.hasOpenLimitOrder(trader, pairIndex, index),
                "NO_LIMIT"
            );
        } else {
            t = storageT.openTrades(trader, pairIndex, index);

            require(t.leverage > 0, "NO_TRADE");

            if (orderType == StorageInterfaceV5.LimitOrder.LIQ) {
                uint256 liqPrice = getTradeLiquidationPrice(t);

                require(
                    t.sl == 0 || (t.buy ? liqPrice > t.sl : liqPrice < t.sl),
                    "HAS_SL"
                );
            } else {
                require(
                    orderType != StorageInterfaceV5.LimitOrder.SL || t.sl > 0,
                    "NO_SL"
                );
                require(
                    orderType != StorageInterfaceV5.LimitOrder.TP || t.tp > 0,
                    "NO_TP"
                );
            }
        }

        NftRewardsInterfaceV6.TriggeredLimitId
            memory triggeredLimitId = NftRewardsInterfaceV6.TriggeredLimitId(
                trader,
                pairIndex,
                index,
                orderType
            );

        if (
            !nftRewards.triggered(triggeredLimitId) ||
            nftRewards.timedOut(triggeredLimitId)
        ) {
            uint256 leveragedPosDai;

            if (orderType == StorageInterfaceV5.LimitOrder.OPEN) {
                StorageInterfaceV5.OpenLimitOrder memory l = storageT
                    .getOpenLimitOrder(trader, pairIndex, index);

                leveragedPosDai = l.positionSize * l.leverage;

                (uint256 priceImpactP, ) = pairInfos.getTradePriceImpact(
                    0,
                    l.pairIndex,
                    l.buy,
                    leveragedPosDai
                );

                require(
                    priceImpactP * l.leverage <=
                        pairInfos.maxNegativePnlOnOpenP(),
                    "PRICE_IMPACT_TOO_HIGH"
                );
            } else {
                leveragedPosDai =
                    (t.initialPosToken *
                        storageT
                            .openTradesInfo(trader, pairIndex, index)
                            .tokenPriceDai *
                        t.leverage) /
                    PRECISION;
            }

            storageT.transferLinkToAggregator(
                sender,
                pairIndex,
                leveragedPosDai
            );

            uint256 orderId = storageT.priceAggregator().getPrice(
                pairIndex,
                orderType == StorageInterfaceV5.LimitOrder.OPEN
                    ? AggregatorInterfaceV6.OrderType.LIMIT_OPEN
                    : AggregatorInterfaceV6.OrderType.LIMIT_CLOSE,
                leveragedPosDai
            );

            storageT.storePendingNftOrder(
                StorageInterfaceV5.PendingNftOrder(
                    sender,
                    nftId,
                    trader,
                    pairIndex,
                    index,
                    orderType
                ),
                orderId
            );

            storageT.priceAggregator().emptyNodeFulFill(
                pairIndex,
                orderId,
                orderType == StorageInterfaceV5.LimitOrder.OPEN
                    ? AggregatorInterfaceV6.OrderType.LIMIT_OPEN
                    : AggregatorInterfaceV6.OrderType.LIMIT_CLOSE
            );

            nftRewards.storeFirstToTrigger(triggeredLimitId, sender);

            emit NftOrderInitiated(orderId, sender, trader, pairIndex);
        } else {
            nftRewards.storeTriggerSameBlock(triggeredLimitId, sender);

            emit NftOrderSameBlock(sender, trader, pairIndex);
        }
    }

    // Avoid stack too deep error in executeOrderByGPT3Bot
    function getTradeLiquidationPrice(StorageInterfaceV5.Trade memory t)
        private
        view
        returns (uint256)
    {
        return
            pairInfos.getTradeLiquidationPrice(
                t.trader,
                t.pairIndex,
                t.index,
                t.openPrice,
                t.buy,
                (t.initialPosToken *
                    storageT
                        .openTradesInfo(t.trader, t.pairIndex, t.index)
                        .tokenPriceDai) / PRECISION,
                t.leverage
            );
    }

    // Market timeout
    function openTradeMarketTimeout(uint256 _order)
        external
        notContract
        notDone
    {
        address sender = _msgSender();

        StorageInterfaceV5.PendingMarketOrder memory o = storageT
            .reqID_pendingMarketOrder(_order);

        StorageInterfaceV5.Trade memory t = o.trade;

        require(
            o.block > 0 && block.number >= o.block + marketOrdersTimeout,
            "WAIT_TIMEOUT"
        );

        require(t.trader == sender, "NOT_YOUR_ORDER");
        require(t.leverage > 0, "WRONG_MARKET_ORDER_TYPE");

        storageT.unregisterPendingMarketOrder(_order, true);
        storageT.transferDai(address(storageT), sender, t.positionSizeDai);

        emit ChainlinkCallbackTimeout(_order, o);
    }

    function closeTradeMarketTimeout(uint256 _order)
        external
        notContract
        notDone
    {
        address sender = _msgSender();

        StorageInterfaceV5.PendingMarketOrder memory o = storageT
            .reqID_pendingMarketOrder(_order);

        StorageInterfaceV5.Trade memory t = o.trade;

        require(
            o.block > 0 && block.number >= o.block + marketOrdersTimeout,
            "WAIT_TIMEOUT"
        );

        require(t.trader == sender, "NOT_YOUR_ORDER");
        require(t.leverage == 0, "WRONG_MARKET_ORDER_TYPE");

        storageT.unregisterPendingMarketOrder(_order, false);

        (bool success, ) = address(this).delegatecall(
            abi.encodeWithSignature(
                "closeTradeMarket(uint256,uint256)",
                t.pairIndex,
                t.index
            )
        );

        if (!success) {
            emit CouldNotCloseTrade(sender, t.pairIndex, t.index);
        }

        emit ChainlinkCallbackTimeout(_order, o);
    }
}

