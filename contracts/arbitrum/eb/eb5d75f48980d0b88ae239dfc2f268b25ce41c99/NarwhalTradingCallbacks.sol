// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;
import "./Initializable.sol";
import "./PausableUpgradeable.sol";
import "./PairInfoInterface.sol";
import "./NarwhalReferralInterface.sol";
import "./LimitOrdersInterface.sol";

contract NarwhalTradingCallbacks is Initializable, PausableUpgradeable {

    StorageInterface public storageT;
    LimitOrdersInterface public limitOrders;
    PairInfoInterface public pairInfos;
    NarwhalReferralInterface public referrals;

    address public Treasury;
    address public MarketingFund;

    // Params
    uint public PRECISION; // 10 decimals
    uint public MAX_SL_P; // -90% PNL
    uint public MAX_GAIN_P; // 900% PnL (10x)

    // Params (adjustable)
    uint public USDTVaultFeeP; // % of closing fee going to USDT vault (eg. 40)
    uint public lpFeeP; // % of closing fee going to NWX/USDT LPs (eg. 20)
    uint public projectFeeP; // % of closing fee going to treasury (eg. 40)
    uint public marketingFeeP; // % of closing fee going to marketing fund


    // Custom data types
    struct AggregatorAnswer {
        uint orderId;
        uint price;
        uint spreadP;
    }

    // Useful to avoid stack too deep errors
    struct Values {
        uint posUSDT;
        uint levPosUSDT;
        uint tokenPriceUSDT;
        int profitP;
        uint price;
        uint liqPrice;
        uint USDTSentToTrader;
        uint reward1;
        uint reward2;
        uint reward3;
        uint reward4;
        uint reward5;
        uint leftoverFees;
        uint totalFees;
    }

    function initialize (
        StorageInterface _storageT,
        LimitOrdersInterface _limitOrders,
        PairInfoInterface _pairInfos,
        NarwhalReferralInterface _referrals,
        uint _USDTVaultFeeP,//90
        uint _lpFeeP,//0
        uint _projectFeeP,//5
        uint256 _marketingFeeP,//5
        address _treasury,
        address _marketingFund
    ) public initializer {
        storageT = _storageT;
        limitOrders = _limitOrders;
        pairInfos = _pairInfos;
        referrals = _referrals;

        require(_USDTVaultFeeP + _lpFeeP + _projectFeeP + _marketingFeeP == 100, "SUM_NOT_100");
        require(address(_storageT) != address(0) &&
            address(_limitOrders) != address(0) &&
            address(_pairInfos) != address(0) &&
            address(_referrals) != address(0), "ZERO_ADDRESS");

        USDTVaultFeeP = _USDTVaultFeeP;
        lpFeeP = _lpFeeP;
        projectFeeP = _projectFeeP;
        marketingFeeP = _marketingFeeP;

        PRECISION = 1e10; // 10 decimals
        MAX_SL_P = 90; // -90% PNL
        MAX_GAIN_P = 900; // 900% PnL (10x)
        
        Treasury = _treasury;
        MarketingFund = _marketingFund;
        __Pausable_init();
    }
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setCoreSettings(
        StorageInterface _storageT,
        LimitOrdersInterface _limitOrders,
        PairInfoInterface _pairInfos,
        NarwhalReferralInterface _referrals,
        uint _USDTVaultFeeP,
        uint _lpFeeP,
        uint _projectFeeP,
        uint256 _marketingFeeP) public onlyGov {
        storageT = _storageT;
        limitOrders = _limitOrders;
        pairInfos = _pairInfos;
        referrals = _referrals;

        require(_USDTVaultFeeP + _lpFeeP + _projectFeeP + _marketingFeeP == 100, "SUM_NOT_100");
        require(address(_storageT) != address(0) &&
            address(_limitOrders) != address(0) &&
            address(_pairInfos) != address(0) &&
            address(_referrals) != address(0), "ZERO_ADDRESS");

        USDTVaultFeeP = _USDTVaultFeeP;
        lpFeeP = _lpFeeP;
        projectFeeP = _projectFeeP;
        marketingFeeP = _marketingFeeP;
    }

    function giveAllowance() public onlyGov {
        storageT.USDT().approve(address(storageT.vault()), type(uint256).max);
        storageT.USDT().approve(address(storageT.pool()), type(uint256).max);
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyPriceAggregator() {
        require(
            msg.sender == address(storageT.priceAggregator()),
            "AGGREGATOR_ONLY"
        );
        _;
    }

    function openTradeMarketCallback(
        AggregatorAnswer memory a
    ) external whenNotPaused onlyPriceAggregator {
        StorageInterface.PendingMarketOrder memory o = storageT
            .reqID_pendingMarketOrder(a.orderId);

        if (o.block == 0) {
            return;
        }

        StorageInterface.Trade memory t = o.trade;

        (uint priceImpactP, uint priceAfterImpact) = pairInfos
            .getTradePriceImpact(
                marketExecutionPrice(
                    a.price,
                    a.spreadP,
                    o.spreadReductionP,
                    t.buy
                ),
                t.pairIndex,
                t.buy,
                t.positionSizeUSDT * t.leverage
            );

        t.openPrice = priceAfterImpact;
        uint maxSlippage = (o.wantedPrice * o.slippageP) / 100 / PRECISION;

        if (a.price == 0 ||
            (
                t.buy
                    ? t.openPrice > o.wantedPrice + maxSlippage
                    : t.openPrice < o.wantedPrice - maxSlippage
            ) ||
            (t.tp > 0 && (t.buy ? t.openPrice >= t.tp : t.openPrice <= t.tp)) ||
            (t.sl > 0 && (t.buy ? t.openPrice <= t.sl : t.openPrice >= t.sl)) ||
            !withinExposureLimits(
                t.pairIndex,
                t.buy,
                t.positionSizeUSDT,
                t.leverage
            ) ||
            priceImpactP * t.leverage > pairInfos.maxNegativePnlOnOpenP()
        ) {
            storageT.transferUSDT(
                address(storageT),
                t.trader,
                t.positionSizeUSDT
            );

        } else {
            registerTrade(t, a.orderId, false);
        }

        storageT.unregisterPendingMarketOrder(a.orderId, true);
    }

    function closeTradeMarketCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator {
        StorageInterface.PendingMarketOrder memory o = storageT
            .reqID_pendingMarketOrder(a.orderId);

        if (o.block == 0) {
            return;
        }

        StorageInterface.Trade memory t = storageT.openTrades(
            o.trade.trader,
            o.trade.pairIndex,
            o.trade.index
        );

        if (t.leverage > 0) {
            StorageInterface.TradeInfo memory i = storageT.openTradesInfo(
                t.trader,
                t.pairIndex,
                t.index
            );

            AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();
            PairsStorageInterface pairsStorage = aggregator.pairsStorage();

            Values memory v;

            v.levPosUSDT =
                (t.initialPosToken * i.tokenPriceUSDT * t.leverage) / PRECISION / 1e8;
            if (a.price == 0) {
                t.initialPosToken -= (v.reward1 * PRECISION) / i.tokenPriceUSDT;
                storageT.updateTrade(t);

            } else {
                v.profitP = currentPercentProfit(
                    t.openPrice,
                    a.price,
                    t.buy,
                    t.leverage
                );
                v.posUSDT = v.levPosUSDT / t.leverage;
                v.USDTSentToTrader = unregisterTrade(
                    t,
                    v.profitP,
                    v.posUSDT,
                    i.openInterestUSDT / t.leverage,
                    (v.levPosUSDT * pairsStorage.pairCloseFeeP(t.pairIndex)) /
                        100000,
                    0
                );
            }
        }

        storageT.unregisterPendingMarketOrder(a.orderId, false);
    }

    function executeOpenOrderCallback(
        AggregatorAnswer memory a
    ) external whenNotPaused onlyPriceAggregator {
        StorageInterface.PendingLimitOrder memory n = storageT
            .reqID_pendingLimitOrder(a.orderId);
        require(n.trader != address(0), "INVALID_ORDER");

        if (a.price > 0 &&
            storageT.hasOpenLimitOrder(n.trader, n.pairIndex, n.index)
        ) {

            StorageInterface.OpenLimitOrder memory o = storageT
                .getOpenLimitOrder(n.trader, n.pairIndex, n.index);

            LimitOrdersInterface.OpenLimitOrderType t = limitOrders
                .openLimitOrderTypes(n.trader, n.pairIndex, n.index);

            (uint priceImpactP, uint priceAfterImpact) = pairInfos
                .getTradePriceImpact(
                    marketExecutionPrice(
                        a.price,
                        a.spreadP,
                        o.spreadReductionP,
                        o.buy
                    ),
                    o.pairIndex,
                    o.buy,
                    o.positionSize * o.leverage
                );

            a.price = priceAfterImpact;
            if (
                (
                    t == LimitOrdersInterface.OpenLimitOrderType.LEGACY
                        ? (a.price >= o.minPrice && a.price <= o.maxPrice)
                        : t == LimitOrdersInterface.OpenLimitOrderType.REVERSAL
                        ? (
                            o.buy
                                ? a.price <= o.maxPrice
                                : a.price >= o.minPrice
                        )
                        : (
                            o.buy
                                ? a.price >= o.minPrice
                                : a.price <= o.maxPrice
                        )
                ) &&
                withinExposureLimits(
                    o.pairIndex,
                    o.buy,
                    o.positionSize,
                    o.leverage
                ) &&
                priceImpactP * o.leverage <= pairInfos.maxNegativePnlOnOpenP()
            ) {
 
                registerTrade(
                        StorageInterface.Trade(
                            o.trader,
                            o.pairIndex,
                            0,
                            0,
                            o.positionSize,
                            t ==
                                LimitOrdersInterface.OpenLimitOrderType.REVERSAL
                                ? o.maxPrice
                                : a.price,
                            o.buy,
                            o.leverage,
                            o.tp,
                            o.sl
                        ),
                        a.orderId,
                        true
                    );

                storageT.unregisterOpenLimitOrder(
                    o.trader,
                    o.pairIndex,
                    o.index
                );
            }
        }

        limitOrders.unregisterTrigger(
            LimitOrdersInterface.TriggeredLimitId(
                n.trader,
                n.pairIndex,
                n.index,
                n.orderType
            )
        );

        storageT.unregisterPendingLimitOrder(a.orderId);
    }

    function executeCloseOrderCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator {
        StorageInterface.PendingLimitOrder memory o = storageT
            .reqID_pendingLimitOrder(a.orderId);
        StorageInterface.Trade memory t = storageT.openTrades(
            o.trader,
            o.pairIndex,
            o.index
        );

        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();

        if (a.price > 0 && t.leverage > 0) {
            StorageInterface.TradeInfo memory i = storageT.openTradesInfo(
                t.trader,
                t.pairIndex,
                t.index
            );

            PairsStorageInterface pairsStored = aggregator.pairsStorage();

            Values memory v;

            v.price = pairsStored.guaranteedSlEnabled(t.pairIndex)
                ? o.orderType == StorageInterface.LimitOrder.TP
                    ? t.tp
                    : o.orderType == StorageInterface.LimitOrder.SL
                    ? t.sl
                    : a.price
                : a.price;

            v.profitP = currentPercentProfit(
                t.openPrice,
                v.price,
                t.buy,
                t.leverage
            );
            v.levPosUSDT =
                (t.initialPosToken * i.tokenPriceUSDT * t.leverage) /
                PRECISION /
                1e8;
            
            v.posUSDT = v.levPosUSDT / t.leverage;

            if (o.orderType == StorageInterface.LimitOrder.LIQ) {
                v.liqPrice = pairInfos.getTradeLiquidationPrice(
                    t.trader,
                    t.pairIndex,
                    t.index,
                    t.openPrice,
                    t.buy,
                    v.posUSDT,
                    t.leverage
                );
                v.reward1 = (
                    t.buy ? a.price <= v.liqPrice : a.price >= v.liqPrice
                )
                    ? (v.posUSDT * 5) / 100
                    : 0;
            } else {
                v.reward1 = ((o.orderType == StorageInterface.LimitOrder.TP &&
                    t.tp > 0 &&
                    (t.buy ? a.price >= t.tp : a.price <= t.tp)) ||
                    (o.orderType == StorageInterface.LimitOrder.SL &&
                        t.sl > 0 &&
                        (t.buy ? a.price <= t.sl : a.price >= t.sl)))
                    ? ((v.levPosUSDT * pairsStored.pairCloseFeeP(t.pairIndex)) /
                        100000) * 5 / 100 : 0;
                
            }

            if (v.reward1 > 0) {
                storageT.transferUSDT(
                    address(storageT),
                    storageT.keeperForOrder(a.orderId),
                    v.reward1
                );
                
                unregisterTrade(
                    t,
                    v.profitP,
                    v.posUSDT - v.reward1,
                    i.openInterestUSDT / t.leverage,
                    (v.levPosUSDT * pairsStored.pairCloseFeeP(t.pairIndex)) /
                        100000 - v.reward1,
                    v.reward1
                );

            }
        }

        limitOrders.unregisterTrigger(
            LimitOrdersInterface.TriggeredLimitId(
                o.trader,
                o.pairIndex,
                o.index,
                o.orderType
            )
        );

        storageT.unregisterPendingLimitOrder(a.orderId);
    }

    function updateSlCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator {
        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();
        AggregatorInterfaceV6_2.PendingSl memory o = aggregator.pendingSlOrders(
            a.orderId
        );

        StorageInterface.Trade memory t = storageT.openTrades(
            o.trader,
            o.pairIndex,
            o.index
        );
        if (t.leverage > 0) {
            StorageInterface.TradeInfo memory i = storageT.openTradesInfo(
                o.trader,
                o.pairIndex,
                o.index
            );

            Values memory v;

            v.tokenPriceUSDT = aggregator.tokenPriceUSDT();
            v.levPosUSDT =
                (t.initialPosToken * i.tokenPriceUSDT * t.leverage) /
                PRECISION /
                1e8 /
                2;

            t.initialPosToken -= (v.reward1 * PRECISION) / i.tokenPriceUSDT;
            storageT.updateTrade(t);

            if (
                a.price > 0 &&
                t.buy == o.buy &&
                t.openPrice == o.openPrice &&
                (t.buy ? o.newSl <= a.price : o.newSl >= a.price)
            ) {
                storageT.updateSl(o.trader, o.pairIndex, o.index, o.newSl);
            }
        }

        aggregator.unregisterPendingSlOrder(a.orderId);
    }

    function registerTrade(
        StorageInterface.Trade memory trade,
        uint256 _orderId,
        bool _limit
    ) private returns (StorageInterface.Trade memory, uint) {
        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();
        PairsStorageInterface pairsStored = aggregator.pairsStorage();
        Values memory v;

        v.levPosUSDT = trade.positionSizeUSDT * trade.leverage;
        v.tokenPriceUSDT = aggregator.tokenPriceUSDT();
        v.totalFees =
            (v.levPosUSDT *
                (pairsStored.pairOpenFeeP(trade.pairIndex))) /
            100000;
        trade.positionSizeUSDT -= v.totalFees;
        address ref = referrals.getReferral(trade.trader);
        if (ref != address(0)) {
            (uint256 discount, uint256 rebate) = referrals
                .getReferralDiscountAndRebate(trade.trader);
            v.reward2 = (v.totalFees * discount) / 1000;

            storageT.transferUSDT(address(storageT), trade.trader, v.reward2);

            if (referrals.isTier3KOL(ref)) {
                v.reward1 = (v.totalFees * rebate) / 1000;
                referrals.incrementTier2Tier3(
                    ref,
                    v.reward1,
                    (v.totalFees * referrals.tier3tier2RebateBonus()) / 1000,
                    v.levPosUSDT
                );
                storageT.transferUSDT(
                    address(storageT),
                    address(referrals),
                    v.reward1 +
                        ((v.totalFees * referrals.tier3tier2RebateBonus()) /
                            1000)
                );
                v.leftoverFees =
                    v.totalFees -
                    (v.reward1 +
                        v.reward2 +
                        ((v.totalFees * referrals.tier3tier2RebateBonus()) /
                            1000));
            } else {
                v.reward1 = (v.totalFees * rebate) / 1000;
                referrals.incrementRewards(ref, v.reward1,v.levPosUSDT);
                storageT.transferUSDT(
                    address(storageT),
                    address(referrals),
                    v.reward1
                );
                v.leftoverFees = v.totalFees - (v.reward1 + v.reward2);
            }
        } else {
            v.leftoverFees = v.totalFees;
        }

        if (_limit) {
            v.reward3 =
                (v.leftoverFees *
                    pairsStored.pairLimitOrderFeeP(trade.pairIndex)) /
                1000;
            storageT.transferUSDT(
                address(storageT),
                storageT.keeperForOrder(_orderId),
                v.reward3
            );
            storageT.transferUSDT(
                address(storageT),
                Treasury,
                (v.leftoverFees * projectFeeP) / 100
            );
        } else {
            storageT.transferUSDT(
                address(storageT),
                Treasury,
                (v.leftoverFees * projectFeeP) / 100
            );
            storageT.transferUSDT(
                address(storageT),
                MarketingFund,
                (v.leftoverFees * marketingFeeP) / 100
            );
        }

        v.reward4 = (v.leftoverFees * USDTVaultFeeP) / 100;
        storageT.transferUSDT(address(storageT), address(this), v.reward4);
        storageT.vault().distributeRewardUSDT(v.reward4, true);

        v.reward5 = (v.leftoverFees * lpFeeP) / 100;
        storageT.distributeLpRewards(v.reward5);

        trade.index = storageT.firstEmptyTradeIndex(
            trade.trader,
            trade.pairIndex
        );
        trade.initialPosToken = trade.positionSizeUSDT * 1e18 / v.tokenPriceUSDT;

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

        pairInfos.storeTradeInitialAccFees(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy
        );
        pairsStored.updateGroupCollateral(
            trade.pairIndex,
            trade.positionSizeUSDT,
            trade.buy,
            true
        );

        storageT.storeTrade(
            trade,
            StorageInterface.TradeInfo(
                0,
                v.tokenPriceUSDT,
                trade.positionSizeUSDT * trade.leverage,
                0,
                0,
                false
            )
        );

        return (trade, v.tokenPriceUSDT);
    }

    function unregisterTrade(
        StorageInterface.Trade memory trade,
        int percentProfit, // PRECISION
        uint currentUSDTPos, // usdtDecimals
        uint initialUSDTPos, // usdtDecimals
        uint closingFeeUSDT, // usdtDecimals
        uint limitFeeUSDT
    ) internal returns (uint USDTSentToTrader) {
        USDTSentToTrader = pairInfos.getTradeValue(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy,
            currentUSDTPos,
            trade.leverage,
            percentProfit,
            closingFeeUSDT + limitFeeUSDT
        );
        Values memory v;
        v.totalFees = closingFeeUSDT;
        if (referrals.getReferral(trade.trader) != address(0)) {

            (uint256 discount, uint256 rebate) = referrals
                .getReferralDiscountAndRebate(trade.trader);
            v.reward2 = (v.totalFees * discount) / 1000;
            storageT.transferUSDT(address(storageT), trade.trader, v.reward2);

            if (referrals.isTier3KOL(referrals.getReferral(trade.trader))) {
                v.reward1 = (v.totalFees * rebate) / 1000;
                referrals.incrementTier2Tier3(
                    referrals.getReferral(trade.trader),
                    v.reward1,
                    (v.totalFees * referrals.tier3tier2RebateBonus()) / 1000,
                    trade.positionSizeUSDT * trade.leverage
                );
                storageT.transferUSDT(
                    address(storageT),
                    address(referrals),
                    v.reward1 +
                        ((v.totalFees * referrals.tier3tier2RebateBonus()) /
                            1000)
                );
                v.leftoverFees =
                    v.totalFees -
                    (v.reward1 +
                        v.reward2 +
                        ((v.totalFees * referrals.tier3tier2RebateBonus()) /
                            1000));
            } else {
                v.reward1 = (v.totalFees * rebate) / 1000;
                referrals.incrementRewards(referrals.getReferral(trade.trader), v.reward1,trade.positionSizeUSDT * trade.leverage);
                storageT.transferUSDT(
                    address(storageT),
                    address(referrals),
                    v.reward1
                );
                v.leftoverFees = v.totalFees - (v.reward1 + v.reward2);
            }
        } else {
            v.leftoverFees = v.totalFees;
        }

        if (trade.positionSizeUSDT > 0) {
            storageT.transferUSDT(
                address(storageT),
                Treasury,
                (v.leftoverFees * projectFeeP) / 100
            );
            storageT.transferUSDT(
                address(storageT),
                MarketingFund,
                (v.leftoverFees * marketingFeeP) / 100
            );

            v.reward4 = (v.leftoverFees * USDTVaultFeeP) / 100;
            storageT.transferUSDT(address(storageT), address(this), v.reward4);
            storageT.vault().distributeRewardUSDT(v.reward4, true);

            v.reward5 = (v.leftoverFees * lpFeeP) / 100;
            storageT.distributeLpRewards(v.reward5);

            uint USDTLeftInStorage = currentUSDTPos - v.totalFees;
            if (USDTSentToTrader > USDTLeftInStorage) {
                storageT.vault().sendUSDTToTrader(
                    trade.trader,
                    USDTSentToTrader - USDTLeftInStorage
                );
                storageT.transferUSDT(
                    address(storageT),
                    trade.trader,
                    USDTLeftInStorage
                );
            } else {
                storageT.vault().receiveUSDTFromTrader(
                    trade.trader,
                    USDTLeftInStorage - USDTSentToTrader,
                    0,
                    false
                );
                storageT.transferUSDT(
                    address(storageT),
                    trade.trader,
                    USDTSentToTrader
                );
            }

        } else {
            storageT.vault().sendUSDTToTrader(trade.trader, USDTSentToTrader);
        }

        storageT.priceAggregator().pairsStorage().updateGroupCollateral(
            trade.pairIndex,
            initialUSDTPos,
            trade.buy,
            false
        );

        storageT.unregisterTrade(trade.trader, trade.pairIndex, trade.index);
    }

    function withinExposureLimits(
        uint pairIndex,
        bool buy,
        uint positionSizeUSDT,
        uint leverage
    ) internal view returns (bool) {
        PairsStorageInterface pairsStored = storageT
            .priceAggregator()
            .pairsStorage();

        uint256 posLev = positionSizeUSDT * leverage;
        uint256 OILimit = storageT.openInterestUSDT(pairIndex, buy ? 0 : 1) + posLev;
        uint256 netOI = storageT.getNetOI(pairIndex, buy);

        return
            OILimit <= storageT.openInterestUSDT(pairIndex, 2) && 
            netOI + posLev <= storageT.openInterestUSDT(pairIndex, buy ? 3 : 4) &&
            pairsStored.groupCollateral(pairIndex, buy) + positionSizeUSDT <=
            pairsStored.groupMaxCollateral(pairIndex);
    }

    function currentPercentProfit(
        uint openPrice,
        uint currentPrice,
        bool buy,
        uint leverage
    ) internal view returns (int p) {
        int maxPnlP = int(MAX_GAIN_P) * int(PRECISION);

        p =
            ((
                buy
                    ? int(currentPrice) - int(openPrice)
                    : int(openPrice) - int(currentPrice)
            ) *
                100 *
                int(PRECISION) *
                int(leverage)) /
            int(openPrice);

        p = p > maxPnlP ? maxPnlP : p;
    }

    function correctTp(
        uint openPrice,
        uint leverage,
        uint tp,
        bool buy
    ) internal view returns (uint) {
        if (
            tp == 0 ||
            currentPercentProfit(openPrice, tp, buy, leverage) ==
            int(MAX_GAIN_P) * int(PRECISION)
        ) {
            uint tpDiff = (openPrice * MAX_GAIN_P) / leverage / 100;

            return
                buy ? openPrice + tpDiff : tpDiff <= openPrice
                    ? openPrice - tpDiff
                    : 0;
        }

        return tp;
    }

    function correctSl(
        uint openPrice,
        uint leverage,
        uint sl,
        bool buy
    ) internal view returns (uint) {
        if (
            sl > 0 &&
            currentPercentProfit(openPrice, sl, buy, leverage) <
            int(MAX_SL_P) * int(PRECISION) * -1
        ) {
            uint slDiff = (openPrice * MAX_SL_P) / leverage / 100;

            return buy ? openPrice - slDiff : openPrice + slDiff;
        }

        return sl;
    }

    function marketExecutionPrice(
        uint price,
        uint spreadP,
        uint spreadReductionP,
        bool long
    ) internal view returns (uint) {
        uint priceDiff = (price *
            (spreadP - (spreadP * spreadReductionP) / 100)) /
            100 /
            PRECISION;

        return long ? price + priceDiff : price - priceDiff;
    }
}

