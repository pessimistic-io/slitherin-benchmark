// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ITradingStorage.sol";
import "./IPairInfos.sol";
import "./ChainUtils.sol";
import "./IBorrowingFees.sol";
import "./TokenInterface.sol";
import "./IFoxifyAffiliation.sol";
import "./IFoxifyReferral.sol";


contract TradingCallbacks {

    uint256 constant PRECISION = 1e10;
    uint256 constant MAX_SL_P = 75; // -75% PNL
    uint256 constant MAX_GAIN_P = 900; // 900% PnL (10x)
    uint256 constant MAX_EXECUTE_TIMEOUT = 5; // 5 blocks

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

    struct AggregatorAnswer {
        uint256 orderId;
        uint256 price;
        uint256 spreadP;
    }

    struct Values {
        uint256 posStable;
        uint256 levPosStable;
        int256 profitP;
        uint256 price;
        uint256 liqPrice;
        uint256 stableSentToTrader;
        uint256 reward1;
        uint256 reward2;
        uint256 reward3;
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

    struct AffiliationUserData {
        uint256 activeId;
        uint256 team;
        IFoxifyAffiliation.NFTData nftData;
    }

    ITradingStorage public storageT;
    IOrderExecutionTokenManagement public orderTokenManagement;
    IPairInfos public pairInfos;
    IBorrowingFees public borrowingFees;
    IFoxifyReferral public referral;
    IFoxifyAffiliation public affiliation;

    bool public isPaused;
    bool public isDone;
    uint256 public canExecuteTimeout; // How long an update to TP/SL/Limit has to wait before it is executable

    mapping(address => mapping(uint256 => mapping(uint256 => mapping(TradeType => LastUpdated))))
        public tradeLastUpdated; // Block numbers for last updated

    mapping(uint256 => uint256) public pairMaxLeverage;

    event OpenMarketExecutedWithAffiliationReferral(
        uint256 indexed orderId,
        ITradingStorage.Trade t,
        bool open,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeStable,
        int256 percentProfit,
        uint256 stableSentToTrader,
        AffiliationUserData affiliationInfo,
        uint256 referralTeamID
    );

    event OpenMarketExecuted(
        uint256 indexed orderId,
        ITradingStorage.Trade t,
        bool open,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeStable,
        int256 percentProfit,
        uint256 stableSentToTrader
    );

    event CloseMarketExecuted(
        uint256 indexed orderId,
        ITradingStorage.Trade t,
        bool open,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeStable,
        int256 percentProfit,
        uint256 stableSentToTrader
    );

    event OpenLimitExecutedWithAffiliationReferral(
        uint256 indexed orderId,
        uint256 limitIndex,
        ITradingStorage.Trade t,
        ITradingStorage.LimitOrder orderType,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeStable,
        int256 percentProfit,
        uint256 stableSentToTrader,
        AffiliationUserData affiliationInfo,
        uint256 referralTeamID
    );

    event OpenLimitExecuted(
        uint256 indexed orderId,
        uint256 limitIndex,
        ITradingStorage.Trade t,
        ITradingStorage.LimitOrder orderType,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeStable,
        int256 percentProfit,
        uint256 stableSentToTrader
    );

    event CloseLimitExecuted(
        uint256 indexed orderId,
        uint256 limitIndex,
        ITradingStorage.Trade t,
        ITradingStorage.LimitOrder orderType,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeStable,
        int256 percentProfit,
        uint256 stableSentToTrader
    );

    event MarketOpenCanceled(
        AggregatorAnswer a,
        ITradingStorage.PendingMarketOrder o,
        CancelReason cancelReason
    );
    event MarketCloseCanceled(
        AggregatorAnswer a,
        ITradingStorage.PendingMarketOrder o,
        CancelReason cancelReason
    );
    event BotOrderCanceled(
        uint256 indexed orderId,
        ITradingStorage.LimitOrder orderType,
        CancelReason cancelReason
    );
    event SlUpdated(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 newSl
    );
    event SlCanceled(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        CancelReason cancelReason
    );

    event CanExecuteTimeoutUpdated(uint newValue);

    event Pause(bool paused);
    event Done(bool done);

    event DevGovRefFeeCharged(address indexed trader, uint256 valueStable);

    event OrderExecutionFeeCharged(address indexed trader, uint256 valueStable);
    event StableWorkPoolFeeCharged(address indexed trader, uint256 valueStable);

    event BorrowingFeeCharged(
        address indexed trader,
        uint256 tradeValueStable,
        uint256 feeValueStable
    );
    event PairMaxLeverageUpdated(
        uint256 indexed pairIndex,
        uint256 maxLeverage
    );

    error TradingCallbacksWrongParams();
    error TradingCallbacksForbidden();
    error TradingCallbacksInvalidAddress(address account);

    modifier onlyGov() {
        isGov();
        _;
    }

    modifier onlyPriceAggregator() {
        isPriceAggregator();
        _;
    }

    modifier notDone() {
        isNotDone();
        _;
    }

    modifier onlyTrading() {
        isTrading();
        _;
    }

    modifier onlyManager() {
        isManager();
        _;
    }

    constructor(
        ITradingStorage _storageT,
        IOrderExecutionTokenManagement _orderTokenManagement,
        IPairInfos _pairInfos,
        IBorrowingFees _borrowingFees,
        address _workPoolToApprove,
        uint256 _canExecuteTimeout
    ) {
        if (
            address(_storageT) == address(0) ||
            address(_orderTokenManagement) == address(0) ||
            address(_pairInfos) == address(0) ||
            address(_borrowingFees) == address(0) ||
            _workPoolToApprove == address(0) ||
            _canExecuteTimeout > MAX_EXECUTE_TIMEOUT
        ) {
            revert TradingCallbacksWrongParams();
        }

        storageT = _storageT;
        orderTokenManagement = _orderTokenManagement;
        pairInfos = _pairInfos;
        borrowingFees = _borrowingFees;

        canExecuteTimeout = _canExecuteTimeout;

        TokenInterface t = storageT.stable();
        t.approve(_workPoolToApprove, type(uint256).max);
    }

    function setPairMaxLeverage(
        uint256 pairIndex,
        uint256 maxLeverage
    ) external onlyManager {
        _setPairMaxLeverage(pairIndex, maxLeverage);
    }

    function setPairMaxLeverageArray(
        uint256[] calldata indices,
        uint256[] calldata values
    ) external onlyManager {
        uint256 len = indices.length;

        if (len != values.length) {
            revert TradingCallbacksWrongParams();
        }

        for (uint256 i; i < len; ) {
            _setPairMaxLeverage(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setCanExecuteTimeout(uint256 _canExecuteTimeout) external onlyGov {
        if (_canExecuteTimeout > MAX_EXECUTE_TIMEOUT) {
            revert TradingCallbacksWrongParams();
        }
        canExecuteTimeout = _canExecuteTimeout;
        emit CanExecuteTimeoutUpdated(_canExecuteTimeout);
    }

    function setReferral(address _referral) external onlyGov returns (bool) {
      if (_referral == address(0)) revert TradingCallbacksInvalidAddress(address(0));
      referral = IFoxifyReferral(_referral);
      return true;
    }

    function setAffiliation(address _affiliation) external onlyGov returns (bool) {
      if (_affiliation == address(0)) revert TradingCallbacksInvalidAddress(address(0));
      affiliation = IFoxifyAffiliation(_affiliation);
      return true;
    }

    function pause() external onlyGov {
        isPaused = !isPaused;

        emit Pause(isPaused);
    }

    function done() external onlyGov {
        isDone = !isDone;

        emit Done(isDone);
    }

    // Callbacks
    function openTradeMarketCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone {
        ITradingStorage.PendingMarketOrder memory o = getPendingMarketOrder(
            a.orderId
        );

        if (o.block == 0) {
            return;
        }

        ITradingStorage.Trade memory t = o.trade;

        (uint256 priceImpactP, uint256 priceAfterImpact) = pairInfos
            .getTradePriceImpact(
                marketExecutionPrice(a.price, a.spreadP, t.buy),
                t.pairIndex,
                t.buy,
                t.positionSizeStable * t.leverage
            );

        t.openPrice = priceAfterImpact;

        uint256 maxSlippage = (o.wantedPrice * o.slippageP) / 100 / PRECISION;

        CancelReason cancelReason = isPaused
            ? CancelReason.PAUSED
            : (
                a.price == 0
                    ? CancelReason.MARKET_CLOSED
                    : (
                        t.buy
                            ? t.openPrice > o.wantedPrice + maxSlippage
                            : t.openPrice < o.wantedPrice - maxSlippage
                    )
                    ? CancelReason.SLIPPAGE
                    : (t.tp > 0 &&
                        (t.buy ? t.openPrice >= t.tp : t.openPrice <= t.tp))
                    ? CancelReason.TP_REACHED
                    : (t.sl > 0 &&
                        (t.buy ? t.openPrice <= t.sl : t.openPrice >= t.sl))
                    ? CancelReason.SL_REACHED
                    : !withinExposureLimits(
                        t.pairIndex,
                        t.buy,
                        t.positionSizeStable,
                        t.leverage
                    )
                    ? CancelReason.EXPOSURE_LIMITS
                    : priceImpactP * t.leverage >
                        pairInfos.maxNegativePnlOnOpenP()
                    ? CancelReason.PRICE_IMPACT
                    : !withinMaxLeverage(t.pairIndex, t.leverage)
                    ? CancelReason.MAX_LEVERAGE
                    : CancelReason.NONE
            );

        if (cancelReason == CancelReason.NONE) {
            ITradingStorage.Trade memory finalTrade = registerTrade(t);

            if (address(affiliation) != address(0) && address(referral) != address(0)) {

                uint256 _activeId = affiliation.usersActiveID(finalTrade.trader);
                AffiliationUserData memory _affiliationData = AffiliationUserData({
                    activeId: _activeId,
                    team: affiliation.usersTeam(finalTrade.trader),
                    nftData: affiliation.data(_activeId)
                });
                uint256 _referralTeamID = referral.userTeamID(finalTrade.trader);

                emit OpenMarketExecutedWithAffiliationReferral(
                    a.orderId,
                    finalTrade,
                    true,
                    finalTrade.openPrice,
                    priceImpactP,
                    finalTrade.positionSizeStable,
                    0,
                    0,
                    _affiliationData,
                    _referralTeamID
                );

            } else {

                emit OpenMarketExecuted(
                    a.orderId,
                    finalTrade,
                    true,
                    finalTrade.openPrice,
                    priceImpactP,
                    finalTrade.positionSizeStable,
                    0,
                    0
                );
            }

        } else {
            uint256 devGovRefFeesStable = storageT.handleDevGovRefFees(
                t.pairIndex,
                t.positionSizeStable * t.leverage,
                true,
                true
            );
            transferFromStorageToAddress(
                t.trader,
                t.positionSizeStable - devGovRefFeesStable
            );

            emit DevGovRefFeeCharged(t.trader, devGovRefFeesStable);
            emit MarketOpenCanceled(
                a,
                o,
                cancelReason
            );
        }

        storageT.unregisterPendingMarketOrder(a.orderId, true);
    }

    function closeTradeMarketCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone {
        ITradingStorage.PendingMarketOrder memory o = getPendingMarketOrder(
            a.orderId
        );

        if (o.block == 0) {
            return;
        }

        ITradingStorage.Trade memory t = getOpenTrade(
            o.trade.trader,
            o.trade.pairIndex,
            o.trade.index
        );

        CancelReason cancelReason = t.leverage == 0
            ? CancelReason.NO_TRADE
            : (a.price == 0 ? CancelReason.MARKET_CLOSED : CancelReason.NONE);

        if (cancelReason != CancelReason.NO_TRADE) {
            ITradingStorage.TradeInfo memory i = getOpenTradeInfo(
                t.trader,
                t.pairIndex,
                t.index
            );
            IAggregator01 aggregator = storageT.priceAggregator();

            Values memory v;
            v.levPosStable = t.positionSizeStable * t.leverage;

            if (cancelReason == CancelReason.NONE) {
                v.profitP = currentPercentProfit(
                    t.openPrice,
                    a.price,
                    t.buy,
                    t.leverage
                );
                v.posStable = v.levPosStable / t.leverage;

                v.stableSentToTrader = unregisterTrade(
                    t,
                    v.profitP,
                    v.posStable,
                    i.openInterestStable,
                    (v.levPosStable *
                        aggregator.pairsStorage().pairCloseFeeP(t.pairIndex)) /
                        100 /
                        PRECISION,
                    (v.levPosStable *
                        aggregator.pairsStorage().pairExecuteLimitOrderFeeP(
                            t.pairIndex
                        )) /
                        100 /
                        PRECISION
                );

                emit CloseMarketExecuted(
                    a.orderId,
                    t,
                    false,
                    a.price,
                    0,
                    v.posStable,
                    v.profitP,
                    v.stableSentToTrader
                );
            } else {
                v.reward1 = storageT.handleDevGovRefFees(
                    t.pairIndex,
                    v.levPosStable,
                    true,
                    true
                );
                t.positionSizeStable -= v.reward1;
                storageT.updateTrade(t);

                emit DevGovRefFeeCharged(t.trader, v.reward1);
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit MarketCloseCanceled(
                a,
                o,
                cancelReason
            );
        }

        storageT.unregisterPendingMarketOrder(a.orderId, false);
    }

    function executeBotOpenOrderCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone {
        ITradingStorage.PendingBotOrder memory n = storageT
            .reqID_pendingBotOrder(a.orderId);

        CancelReason cancelReason = isPaused
            ? CancelReason.PAUSED
            : (
                a.price == 0
                    ? CancelReason.MARKET_CLOSED
                    : !storageT.hasOpenLimitOrder(
                        n.trader,
                        n.pairIndex,
                        n.index
                    )
                    ? CancelReason.NO_TRADE
                    : CancelReason.NONE
            );

        if (cancelReason == CancelReason.NONE) {
            ITradingStorage.OpenLimitOrder memory o = storageT
                .getOpenLimitOrder(n.trader, n.pairIndex, n.index);

            IOrderExecutionTokenManagement.OpenLimitOrderType t = orderTokenManagement
                    .openLimitOrderTypes(n.trader, n.pairIndex, n.index);

            (uint256 priceImpactP, uint256 priceAfterImpact) = pairInfos
                .getTradePriceImpact(
                    marketExecutionPrice(a.price, a.spreadP, o.buy),
                    o.pairIndex,
                    o.buy,
                    o.positionSize * o.leverage
                );

            a.price = priceAfterImpact;

            cancelReason = (
                t == IOrderExecutionTokenManagement.OpenLimitOrderType.LEGACY
                    ? (a.price < o.minPrice || a.price > o.maxPrice)
                    : (
                        t ==
                            IOrderExecutionTokenManagement
                                .OpenLimitOrderType
                                .REVERSAL
                            ? (
                                o.buy
                                    ? a.price > o.maxPrice
                                    : a.price < o.minPrice
                            )
                            : (
                                o.buy
                                    ? a.price < o.minPrice
                                    : a.price > o.maxPrice
                            )
                    )
            )
                ? CancelReason.NOT_HIT
                : (
                    !withinExposureLimits(
                        o.pairIndex,
                        o.buy,
                        o.positionSize,
                        o.leverage
                    )
                        ? CancelReason.EXPOSURE_LIMITS
                        : priceImpactP * o.leverage >
                            pairInfos.maxNegativePnlOnOpenP()
                        ? CancelReason.PRICE_IMPACT
                        : !withinMaxLeverage(o.pairIndex, o.leverage)
                        ? CancelReason.MAX_LEVERAGE
                        : CancelReason.NONE
                );

            if (cancelReason == CancelReason.NONE) {
                ITradingStorage.Trade memory finalTrade = registerTrade(
                    ITradingStorage.Trade(
                        o.trader,
                        o.pairIndex,
                        0,
                        o.positionSize,
                        t ==
                            IOrderExecutionTokenManagement
                                .OpenLimitOrderType
                                .REVERSAL
                            ? o.maxPrice // o.minPrice = o.maxPrice in that case
                            : a.price,
                        o.buy,
                        o.leverage,
                        o.tp,
                        o.sl
                    )
                );

                storageT.unregisterOpenLimitOrder(
                    o.trader,
                    o.pairIndex,
                    o.index
                );

                if (address(affiliation) != address(0) && address(referral) != address(0)) {

                    uint256 _activeId = affiliation.usersActiveID(finalTrade.trader);
                    AffiliationUserData memory _affiliationData = AffiliationUserData({
                        activeId: _activeId,
                        team: affiliation.usersTeam(finalTrade.trader),
                        nftData: affiliation.data(_activeId)
                    });
                    uint256 _referralTeamID = referral.userTeamID(finalTrade.trader);

                    emit OpenLimitExecutedWithAffiliationReferral(
                        a.orderId,
                        n.index,
                        finalTrade,
                        ITradingStorage.LimitOrder.OPEN,
                        finalTrade.openPrice,
                        priceImpactP,
                        finalTrade.positionSizeStable,
                        0,
                        0,
                        _affiliationData,
                        _referralTeamID
                    );

                } else {

                    emit OpenLimitExecuted(
                        a.orderId,
                        n.index,
                        finalTrade,
                        ITradingStorage.LimitOrder.OPEN,
                        finalTrade.openPrice,
                        priceImpactP,
                        finalTrade.positionSizeStable,
                        0,
                        0
                    );
                }
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit BotOrderCanceled(
                a.orderId,
                ITradingStorage.LimitOrder.OPEN,
                cancelReason
            );
        }

        storageT.unregisterPendingBotOrder(a.orderId);
    }

    function executeBotCloseOrderCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone {
        ITradingStorage.PendingBotOrder memory o = storageT
            .reqID_pendingBotOrder(a.orderId);
        ITradingStorage.Trade memory t = getOpenTrade(
            o.trader,
            o.pairIndex,
            o.index
        );

        IAggregator01 aggregator = storageT.priceAggregator();

        CancelReason cancelReason = a.price == 0
            ? CancelReason.MARKET_CLOSED
            : (t.leverage == 0 ? CancelReason.NO_TRADE : CancelReason.NONE);

        if (cancelReason == CancelReason.NONE) {
            ITradingStorage.TradeInfo memory i = getOpenTradeInfo(
                t.trader,
                t.pairIndex,
                t.index
            );

            IPairsStorage pairsStored = aggregator.pairsStorage();

            Values memory v;

            v.price = pairsStored.guaranteedSlEnabled(t.pairIndex)
                ? o.orderType == ITradingStorage.LimitOrder.TP
                    ? t.tp
                    : o.orderType == ITradingStorage.LimitOrder.SL
                    ? t.sl
                    : a.price
                : a.price;

            v.levPosStable = t.positionSizeStable * t.leverage;
            v.posStable = v.levPosStable / t.leverage;

            if (o.orderType == ITradingStorage.LimitOrder.LIQ) {
                v.liqPrice = borrowingFees.getTradeLiquidationPrice(
                    IBorrowingFees.LiqPriceInput(
                        t.trader,
                        t.pairIndex,
                        t.index,
                        t.openPrice,
                        t.buy,
                        v.posStable,
                        t.leverage
                    )
                );

                // Bot reward in Stable
                v.reward1 = (
                    t.buy ? a.price <= v.liqPrice : a.price >= v.liqPrice
                )
                    ? (v.posStable * 5) / 100
                    : 0;
            } else {
                // Bot reward in Stable
                v.reward1 = ((o.orderType == ITradingStorage.LimitOrder.TP &&
                    t.tp > 0 &&
                    (t.buy ? a.price >= t.tp : a.price <= t.tp)) ||
                    (o.orderType == ITradingStorage.LimitOrder.SL &&
                        t.sl > 0 &&
                        (t.buy ? a.price <= t.sl : a.price >= t.sl)))
                    ? (v.levPosStable *
                        pairsStored.pairExecuteLimitOrderFeeP(t.pairIndex)) /
                        100 /
                        PRECISION
                    : 0;
            }

            cancelReason = v.reward1 == 0
                ? CancelReason.NOT_HIT
                : CancelReason.NONE;

            if (cancelReason == CancelReason.NONE) {
                v.profitP = currentPercentProfit(
                    t.openPrice,
                    v.price,
                    t.buy,
                    t.leverage
                );

                v.stableSentToTrader = unregisterTrade(
                    t,
                    v.profitP,
                    v.posStable,
                    i.openInterestStable,
                    o.orderType == ITradingStorage.LimitOrder.LIQ
                        ? v.reward1
                        : (v.levPosStable *
                            pairsStored.pairCloseFeeP(t.pairIndex)) /
                            100 /
                            PRECISION,
                    v.reward1
                );

                emit CloseLimitExecuted(
                    a.orderId,
                    o.index,
                    t,
                    o.orderType,
                    v.price,
                    0,
                    v.posStable,
                    v.profitP,
                    v.stableSentToTrader
                );
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit BotOrderCanceled(a.orderId, o.orderType, cancelReason);
        }

        storageT.unregisterPendingBotOrder(a.orderId);
    }

    function updateSlCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone {
        IAggregator01 aggregator = storageT.priceAggregator();
        IAggregator01.PendingSl memory o = aggregator.pendingSlOrders(
            a.orderId
        );

        ITradingStorage.Trade memory t = getOpenTrade(
            o.trader,
            o.pairIndex,
            o.index
        );

        CancelReason cancelReason = t.leverage == 0
            ? CancelReason.NO_TRADE
            : CancelReason.NONE;

        if (cancelReason == CancelReason.NONE) {
            Values memory v;

            v.levPosStable = (t.positionSizeStable * t.leverage) / 2;

            v.reward1 = storageT.handleDevGovRefFees(
                t.pairIndex,
                v.levPosStable,
                false,
                false
            );

            t.positionSizeStable -= v.reward1;
            storageT.updateTrade(t);

            emit DevGovRefFeeCharged(t.trader, v.reward1);

            cancelReason = a.price == 0
                ? CancelReason.MARKET_CLOSED
                : (
                    (t.buy != o.buy || t.openPrice != o.openPrice)
                        ? CancelReason.WRONG_TRADE
                        : (t.buy ? o.newSl > a.price : o.newSl < a.price)
                        ? CancelReason.SL_REACHED
                        : CancelReason.NONE
                );

            if (cancelReason == CancelReason.NONE) {
                storageT.updateSl(o.trader, o.pairIndex, o.index, o.newSl);
                LastUpdated storage l = tradeLastUpdated[o.trader][o.pairIndex][
                    o.index
                ][TradeType.MARKET];
                l.sl = uint32(ChainUtils.getBlockNumber());

                emit SlUpdated(
                    a.orderId,
                    o.trader,
                    o.pairIndex,
                    o.index,
                    o.newSl
                );
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit SlCanceled(
                a.orderId,
                o.trader,
                o.pairIndex,
                o.index,
                cancelReason
            );
        }

        storageT.orderTokenManagement().addAggregatorFund();
        aggregator.unregisterPendingSlOrder(a.orderId);
    }

    function setTradeLastUpdated(
        SimplifiedTradeId calldata _id,
        LastUpdated memory _lastUpdated
    ) external onlyTrading {
        tradeLastUpdated[_id.trader][_id.pairIndex][_id.index][
            _id.tradeType
        ] = _lastUpdated;
    }

    function getAllPairsMaxLeverage() external view returns (uint256[] memory) {
        uint256 len = getPairsStorage().pairsCount();
        uint256[] memory lev = new uint256[](len);

        for (uint256 i; i < len; ) {
            lev[i] = pairMaxLeverage[i];
            unchecked {
                ++i;
            }
        }
        return lev;
    }

    function _setPairMaxLeverage(
        uint256 pairIndex,
        uint256 maxLeverage
    ) private {
        pairMaxLeverage[pairIndex] = maxLeverage;
        emit PairMaxLeverageUpdated(pairIndex, maxLeverage);
    }

    function registerTrade(
        ITradingStorage.Trade memory trade
    ) private returns (ITradingStorage.Trade memory) {
        IAggregator01 aggregator = storageT.priceAggregator();
        IPairsStorage pairsStored = aggregator.pairsStorage();

        Values memory v;

        v.levPosStable = trade.positionSizeStable * trade.leverage;

        // 1. Charge opening fee
        v.reward2 = storageT.handleDevGovRefFees(
            trade.pairIndex,
            v.levPosStable,
            true,
            true
        );

        trade.positionSizeStable -= v.reward2;

        emit DevGovRefFeeCharged(trade.trader, v.reward2);

        // 2. Charge OrderExecutionReward
        v.reward2 =
            (v.levPosStable *
                pairsStored.pairExecuteLimitOrderFeeP(trade.pairIndex)) /
            100 /
            PRECISION;
        trade.positionSizeStable -= v.reward2;

        // 3. Distribute OrderExecutionReward
        distributeOrderExecutionReward(trade.trader, v.reward2);
        storageT.orderTokenManagement().addAggregatorFund();

        // 4. Set trade final details
        trade.index = storageT.firstEmptyTradeIndex(
            trade.trader,
            trade.pairIndex
        );

        trade.tp = correctTp(
            trade.openPrice,
            trade.leverage,
            trade.tp,
            trade.buy
        );
        trade.sl = correctSl(
            trade.openPrice,
            trade.leverage,
            trade.sl,
            trade.buy
        );

        // 5. Call other contracts
        pairInfos.storeTradeInitialAccFees(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy
        );
        pairsStored.updateGroupCollateral(
            trade.pairIndex,
            trade.positionSizeStable,
            trade.buy,
            true
        );
        borrowingFees.handleTradeAction(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.positionSizeStable * trade.leverage,
            true,
            trade.buy
        );

        // 6. Store final trade in storage contract
        storageT.storeTrade(
            trade,
            ITradingStorage.TradeInfo(
                0,
                trade.positionSizeStable * trade.leverage,
                0,
                0,
                false
            )
        );

        // 7. Store tradeLastUpdated
        LastUpdated storage lastUpdated = tradeLastUpdated[trade.trader][
            trade.pairIndex
        ][trade.index][TradeType.MARKET];
        uint32 currBlock = uint32(ChainUtils.getBlockNumber());
        lastUpdated.tp = currBlock;
        lastUpdated.sl = currBlock;
        lastUpdated.created = currBlock;

        return (trade);
    }

    function unregisterTrade(
        ITradingStorage.Trade memory trade,
        int256 percentProfit,
        uint256 currentStablePos,
        uint256 openInterestStable,
        uint256 closingFeeStable,
        uint256 botFeeStable
    ) private returns (uint256 stableSentToTrader) {
        IWorkPool workPool = storageT.workPool();

        // 1. Calculate net PnL (after all closing and holding fees)
        (stableSentToTrader, ) = _getTradeValue(
            trade,
            currentStablePos,
            percentProfit,
            closingFeeStable + botFeeStable
        );

        // 2. Calls to other contracts
        borrowingFees.handleTradeAction(
            trade.trader,
            trade.pairIndex,
            trade.index,
            openInterestStable,
            false,
            trade.buy
        );
        getPairsStorage().updateGroupCollateral(
            trade.pairIndex,
            openInterestStable / trade.leverage,
            trade.buy,
            false
        );

        // 3. Unregister trade from storage
        storageT.unregisterTrade(trade.trader, trade.pairIndex, trade.index);

        Values memory v;

        // 4.1.1 Stable workPool reward
        v.reward2 = closingFeeStable;
        transferFromStorageToAddress(address(this), v.reward2);
        TokenInterface stableToken = storageT.stable();
        stableToken.approve(address(workPool), type(uint256).max);
        workPool.distributeReward(v.reward2);

        emit StableWorkPoolFeeCharged(trade.trader, v.reward2);

        // 4.1.2 OrderExecutionReward
        distributeOrderExecutionReward(trade.trader, botFeeStable);
        storageT.orderTokenManagement().addAggregatorFund();

        // 4.1.3 Take Stable from workPool if winning trade
        // or send Stable to workPool if losing trade
        uint256 stableLeftInStorage = currentStablePos - v.reward2;

        if (stableSentToTrader > stableLeftInStorage) {
            workPool.sendAssets(stableSentToTrader - stableLeftInStorage, trade.trader);
            transferFromStorageToAddress(trade.trader, stableLeftInStorage);
        } else {
            sendToWorkPool(stableLeftInStorage - stableSentToTrader, trade.trader);
            transferFromStorageToAddress(trade.trader, stableSentToTrader);
        }
    }

    function _getTradeValue(
        ITradingStorage.Trade memory trade,
        uint256 currentStablePos,
        int256 percentProfit,
        uint256 closingFees
    ) private returns (uint256 value, uint256 borrowingFee) {
        int256 netProfitP;

        (netProfitP, borrowingFee) = _getBorrowingFeeAdjustedPercentProfit(
            trade,
            currentStablePos,
            percentProfit
        );
        value = pairInfos.getTradeValue(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy,
            currentStablePos,
            trade.leverage,
            netProfitP,
            closingFees
        );

        emit BorrowingFeeCharged(trade.trader, value, borrowingFee);
    }

    function distributeOrderExecutionReward(
        address trader,
        uint256 amountStable
    ) private {
        transferFromStorageToAddress(address(this), amountStable);
        address _orderTokenManagement = address(
            storageT.orderTokenManagement()
        );
        storageT.stable().transfer(_orderTokenManagement, amountStable);
        emit OrderExecutionFeeCharged(trader, amountStable);
    }

    function sendToWorkPool(uint256 amountStable, address trader) private {
        transferFromStorageToAddress(address(this), amountStable);
        storageT.workPool().receiveAssets(amountStable, trader);
    }

    function transferFromStorageToAddress(
        address to,
        uint256 amountStable
    ) private {
        storageT.transferStable(address(storageT), to, amountStable);
    }

    function isGov() private view {
        if (msg.sender != storageT.gov()) {
            revert TradingCallbacksForbidden();
        }
    }

    function isPriceAggregator() private view {
        if (msg.sender != address(storageT.priceAggregator())) {
            revert TradingCallbacksForbidden();
        }
    }

    function isNotDone() private view {
        if (isDone) {
            revert TradingCallbacksForbidden();
        }
    }

    function isTrading() private view {
        if (msg.sender != storageT.trading()) {
            revert TradingCallbacksForbidden();
        }
    }

    function isManager() private view {
        if (msg.sender != pairInfos.manager()) {
            revert TradingCallbacksForbidden();
        }
    }

    function _getBorrowingFeeAdjustedPercentProfit(
        ITradingStorage.Trade memory trade,
        uint256 currentStablePos,
        int256 percentProfit
    ) private view returns (int256 netProfitP, uint256 borrowingFee) {
        borrowingFee = borrowingFees.getTradeBorrowingFee(
            IBorrowingFees.BorrowingFeeInput(
                trade.trader,
                trade.pairIndex,
                trade.index,
                trade.buy,
                currentStablePos,
                trade.leverage
            )
        );
        netProfitP =
            percentProfit -
            int256((borrowingFee * 100 * PRECISION) / currentStablePos);
    }

    function withinMaxLeverage(
        uint256 pairIndex,
        uint256 leverage
    ) private view returns (bool) {
        uint256 pairMaxLev = pairMaxLeverage[pairIndex];
        return
            pairMaxLev == 0
                ? leverage <= getPairsStorage().pairMaxLeverage(pairIndex)
                : leverage <= pairMaxLev;
    }

    function withinExposureLimits(
        uint256 pairIndex,
        bool buy,
        uint256 positionSizeStable,
        uint256 leverage
    ) private view returns (bool) {
        uint256 levPositionSizeStable = positionSizeStable * leverage;

        return
            storageT.openInterestStable(pairIndex, buy ? 0 : 1) +
                levPositionSizeStable <=
            storageT.openInterestStable(pairIndex, 2) &&
            borrowingFees.withinMaxGroupOi(pairIndex, buy, levPositionSizeStable);
    }

    function getPendingMarketOrder(
        uint256 orderId
    ) private view returns (ITradingStorage.PendingMarketOrder memory) {
        return storageT.reqID_pendingMarketOrder(orderId);
    }

    function getPairsStorage() private view returns (IPairsStorage) {
        return storageT.priceAggregator().pairsStorage();
    }

    function getOpenTrade(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) private view returns (ITradingStorage.Trade memory) {
        return storageT.openTrades(trader, pairIndex, index);
    }

    function getOpenTradeInfo(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) private view returns (ITradingStorage.TradeInfo memory) {
        return storageT.openTradesInfo(trader, pairIndex, index);
    }

    function currentPercentProfit(
        uint256 openPrice,
        uint256 currentPrice,
        bool buy,
        uint256 leverage
    ) private pure returns (int256 p) {
        int256 maxPnlP = int256(MAX_GAIN_P) * int256(PRECISION);

        p =
            ((
                buy
                    ? int256(currentPrice) - int256(openPrice)
                    : int256(openPrice) - int256(currentPrice)
            ) *
                100 *
                int256(PRECISION) *
                int256(leverage)) /
            int256(openPrice);

        p = p > maxPnlP ? maxPnlP : p;
    }

    function correctTp(
        uint256 openPrice,
        uint256 leverage,
        uint256 tp,
        bool buy
    ) private pure returns (uint256) {
        if (
            tp == 0 ||
            currentPercentProfit(openPrice, tp, buy, leverage) ==
            int256(MAX_GAIN_P) * int256(PRECISION)
        ) {
            uint256 tpDiff = (openPrice * MAX_GAIN_P) / leverage / 100;

            return
                buy
                    ? openPrice + tpDiff
                    : (tpDiff <= openPrice ? openPrice - tpDiff : 0);
        }

        return tp;
    }

    function correctSl(
        uint256 openPrice,
        uint256 leverage,
        uint256 sl,
        bool buy
    ) private pure returns (uint256) {
        if (
            sl > 0 &&
            currentPercentProfit(openPrice, sl, buy, leverage) <
            int256(MAX_SL_P) * int256(PRECISION) * -1
        ) {
            uint256 slDiff = (openPrice * MAX_SL_P) / leverage / 100;

            return buy ? openPrice - slDiff : openPrice + slDiff;
        }

        return sl;
    }

    function marketExecutionPrice(
        uint256 price,
        uint256 spreadP,
        bool long
    ) private pure returns (uint256) {
        uint256 priceDiff = (price * spreadP) / 100 / PRECISION;

        return long ? price + priceDiff : price - priceDiff;
    }
}

