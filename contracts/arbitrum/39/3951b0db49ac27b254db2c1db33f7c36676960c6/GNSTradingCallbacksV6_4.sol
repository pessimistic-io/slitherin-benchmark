// SPDX-License-Identifier: MIT
import "./Initializable.sol";

import "./StorageInterfaceV5.sol";
import "./GNSPairInfosInterfaceV6.sol";
import "./GNSReferralsInterfaceV6_2.sol";
import "./GNSStakingInterfaceV6_2.sol";
import "./ChainUtils.sol";
import "./GNSBorrowingFeesInterfaceV6_4.sol";

pragma solidity 0.8.17;

contract GNSTradingCallbacksV6_4 is Initializable {
    // Contracts (constant)
    StorageInterfaceV5 public storageT;
    NftRewardsInterfaceV6_3_1 public nftRewards;
    GNSPairInfosInterfaceV6 public pairInfos;
    GNSReferralsInterfaceV6_2 public referrals;
    GNSStakingInterfaceV6_2 public staking;

    // Params (constant)
    uint constant PRECISION = 1e10; // 10 decimals

    uint constant MAX_SL_P = 75; // -75% PNL
    uint constant MAX_GAIN_P = 900; // 900% PnL (10x)
    uint constant MAX_EXECUTE_TIMEOUT = 5; // 5 blocks

    // Params (adjustable)
    uint public daiVaultFeeP; // % of closing fee going to DAI vault (eg. 40)
    uint public lpFeeP; // % of closing fee going to GNS/DAI LPs (eg. 20)
    uint public sssFeeP; // % of closing fee going to GNS staking (eg. 40)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract
    uint public canExecuteTimeout; // How long an update to TP/SL/Limit has to wait before it is executable

    // Last Updated State
    mapping(address => mapping(uint => mapping(uint => mapping(TradeType => LastUpdated)))) public tradeLastUpdated; // Block numbers for last updated

    // v6.3.2 Storage/State
    GNSBorrowingFeesInterfaceV6_4 public borrowingFees;

    mapping(uint => uint) public pairMaxLeverage;

    // v6.4 Storage
    mapping(address => mapping(uint => mapping(uint => mapping(TradeType => TradeData)))) public tradeData; // More storage for trades / limit orders

    // Custom data types
    struct AggregatorAnswer {
        uint orderId;
        uint price;
        uint spreadP;
        uint64 open;
        uint64 high;
        uint64 low;
    }

    // Useful to avoid stack too deep errors
    struct Values {
        uint posDai;
        uint levPosDai;
        uint tokenPriceDai;
        int profitP;
        uint price;
        uint liqPrice;
        uint daiSentToTrader;
        uint reward1;
        uint reward2;
        uint reward3;
        bool exactExecution;
    }

    struct SimplifiedTradeId {
        address trader;
        uint pairIndex;
        uint index;
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
        uint216 _placeholder; // for potential future data
    }

    struct OpenTradePrepInput {
        uint executionPrice;
        uint wantedPrice;
        uint marketPrice;
        uint spreadP;
        uint spreadReductionP;
        bool buy;
        uint pairIndex;
        uint positionSize;
        uint leverage;
        uint maxSlippageP;
        uint tp;
        uint sl;
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

    // Events
    event MarketExecuted(
        uint indexed orderId,
        StorageInterfaceV5.Trade t,
        bool open,
        uint price,
        uint priceImpactP,
        uint positionSizeDai,
        int percentProfit, // before fees
        uint daiSentToTrader
    );

    event LimitExecuted(
        uint indexed orderId,
        uint limitIndex,
        StorageInterfaceV5.Trade t,
        address indexed nftHolder,
        StorageInterfaceV5.LimitOrder orderType,
        uint price,
        uint priceImpactP,
        uint positionSizeDai,
        int percentProfit,
        uint daiSentToTrader,
        bool exactExecution
    );

    event MarketOpenCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        CancelReason cancelReason
    );
    event MarketCloseCanceled(
        uint indexed orderId,
        address indexed trader,
        uint indexed pairIndex,
        uint index,
        CancelReason cancelReason
    );
    event NftOrderCanceled(
        uint indexed orderId,
        address indexed nftHolder,
        StorageInterfaceV5.LimitOrder orderType,
        CancelReason cancelReason
    );

    event ClosingFeeSharesPUpdated(uint daiVaultFeeP, uint lpFeeP, uint sssFeeP);
    event CanExecuteTimeoutUpdated(uint newValue);

    event Pause(bool paused);
    event Done(bool done);

    event DevGovFeeCharged(address indexed trader, uint valueDai);
    event ReferralFeeCharged(address indexed trader, uint valueDai);
    event NftBotFeeCharged(address indexed trader, uint valueDai);
    event SssFeeCharged(address indexed trader, uint valueDai);
    event DaiVaultFeeCharged(address indexed trader, uint valueDai);
    event BorrowingFeeCharged(address indexed trader, uint tradeValueDai, uint feeValueDai);
    event PairMaxLeverageUpdated(uint indexed pairIndex, uint maxLeverage);

    // Custom errors (save gas)
    error WrongParams();
    error Forbidden();

    function initialize(
        StorageInterfaceV5 _storageT,
        NftRewardsInterfaceV6_3_1 _nftRewards,
        GNSPairInfosInterfaceV6 _pairInfos,
        GNSReferralsInterfaceV6_2 _referrals,
        GNSStakingInterfaceV6_2 _staking,
        address vaultToApprove,
        uint _daiVaultFeeP,
        uint _lpFeeP,
        uint _sssFeeP,
        uint _canExecuteTimeout
    ) external initializer {
        if (
            address(_storageT) == address(0) ||
            address(_nftRewards) == address(0) ||
            address(_pairInfos) == address(0) ||
            address(_referrals) == address(0) ||
            address(_staking) == address(0) ||
            vaultToApprove == address(0) ||
            _daiVaultFeeP + _lpFeeP + _sssFeeP != 100 ||
            _canExecuteTimeout > MAX_EXECUTE_TIMEOUT
        ) {
            revert WrongParams();
        }

        storageT = _storageT;
        nftRewards = _nftRewards;
        pairInfos = _pairInfos;
        referrals = _referrals;
        staking = _staking;

        daiVaultFeeP = _daiVaultFeeP;
        lpFeeP = _lpFeeP;
        sssFeeP = _sssFeeP;

        canExecuteTimeout = _canExecuteTimeout;

        TokenInterfaceV5 t = storageT.dai();
        t.approve(address(staking), type(uint256).max);
        t.approve(vaultToApprove, type(uint256).max);
    }

    function initializeV2(GNSBorrowingFeesInterfaceV6_4 _borrowingFees) external reinitializer(2) {
        if (address(_borrowingFees) == address(0)) {
            revert WrongParams();
        }
        borrowingFees = _borrowingFees;
    }

    // Modifiers
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

    // Saving code size by calling these functions inside modifiers
    function isGov() private view {
        if (msg.sender != storageT.gov()) {
            revert Forbidden();
        }
    }

    function isPriceAggregator() private view {
        if (msg.sender != address(storageT.priceAggregator())) {
            revert Forbidden();
        }
    }

    function isNotDone() private view {
        if (isDone) {
            revert Forbidden();
        }
    }

    function isTrading() private view {
        if (msg.sender != storageT.trading()) {
            revert Forbidden();
        }
    }

    function isManager() private view {
        if (msg.sender != pairInfos.manager()) {
            revert Forbidden();
        }
    }

    // Manage params
    function setPairMaxLeverage(uint pairIndex, uint maxLeverage) external onlyManager {
        _setPairMaxLeverage(pairIndex, maxLeverage);
    }

    function setPairMaxLeverageArray(uint[] calldata indices, uint[] calldata values) external onlyManager {
        uint len = indices.length;

        if (len != values.length) {
            revert WrongParams();
        }

        for (uint i; i < len; ) {
            _setPairMaxLeverage(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setPairMaxLeverage(uint pairIndex, uint maxLeverage) private {
        pairMaxLeverage[pairIndex] = maxLeverage;
        emit PairMaxLeverageUpdated(pairIndex, maxLeverage);
    }

    function setClosingFeeSharesP(uint _daiVaultFeeP, uint _lpFeeP, uint _sssFeeP) external onlyGov {
        if (_daiVaultFeeP + _lpFeeP + _sssFeeP != 100) {
            revert WrongParams();
        }

        daiVaultFeeP = _daiVaultFeeP;
        lpFeeP = _lpFeeP;
        sssFeeP = _sssFeeP;

        emit ClosingFeeSharesPUpdated(_daiVaultFeeP, _lpFeeP, _sssFeeP);
    }

    function setCanExecuteTimeout(uint _canExecuteTimeout) external onlyGov {
        if (_canExecuteTimeout > MAX_EXECUTE_TIMEOUT) {
            revert WrongParams();
        }
        canExecuteTimeout = _canExecuteTimeout;
        emit CanExecuteTimeoutUpdated(_canExecuteTimeout);
    }

    // Manage state
    function pause() external onlyGov {
        isPaused = !isPaused;

        emit Pause(isPaused);
    }

    function done() external onlyGov {
        isDone = !isDone;

        emit Done(isDone);
    }

    // Callbacks
    function openTradeMarketCallback(AggregatorAnswer memory a) external onlyPriceAggregator notDone {
        StorageInterfaceV5.PendingMarketOrder memory o = getPendingMarketOrder(a.orderId);

        if (o.block == 0) {
            return;
        }

        StorageInterfaceV5.Trade memory t = o.trade;

        (uint priceImpactP, uint priceAfterImpact, CancelReason cancelReason) = _openTradePrep(
            OpenTradePrepInput(
                a.price,
                o.wantedPrice,
                a.price,
                a.spreadP,
                o.spreadReductionP,
                t.buy,
                t.pairIndex,
                t.positionSizeDai,
                t.leverage,
                o.slippageP,
                t.tp,
                t.sl
            )
        );

        t.openPrice = priceAfterImpact;

        if (cancelReason == CancelReason.NONE) {
            (StorageInterfaceV5.Trade memory finalTrade, uint tokenPriceDai) = registerTrade(t, 1500, 0);

            emit MarketExecuted(
                a.orderId,
                finalTrade,
                true,
                finalTrade.openPrice,
                priceImpactP,
                (finalTrade.initialPosToken * tokenPriceDai) / PRECISION,
                0,
                0
            );
        } else {
            uint devGovFeesDai = storageT.handleDevGovFees(t.pairIndex, t.positionSizeDai * t.leverage, true, true);
            transferFromStorageToAddress(t.trader, t.positionSizeDai - devGovFeesDai);

            emit DevGovFeeCharged(t.trader, devGovFeesDai);
            emit MarketOpenCanceled(a.orderId, t.trader, t.pairIndex, cancelReason);
        }

        storageT.unregisterPendingMarketOrder(a.orderId, true);
    }

    function closeTradeMarketCallback(AggregatorAnswer memory a) external onlyPriceAggregator notDone {
        StorageInterfaceV5.PendingMarketOrder memory o = getPendingMarketOrder(a.orderId);

        if (o.block == 0) {
            return;
        }

        StorageInterfaceV5.Trade memory t = getOpenTrade(o.trade.trader, o.trade.pairIndex, o.trade.index);

        CancelReason cancelReason = t.leverage == 0
            ? CancelReason.NO_TRADE
            : (a.price == 0 ? CancelReason.MARKET_CLOSED : CancelReason.NONE);

        if (cancelReason != CancelReason.NO_TRADE) {
            StorageInterfaceV5.TradeInfo memory i = getOpenTradeInfo(t.trader, t.pairIndex, t.index);
            AggregatorInterfaceV6_4 aggregator = storageT.priceAggregator();

            Values memory v;
            v.levPosDai = (t.initialPosToken * i.tokenPriceDai * t.leverage) / PRECISION;
            v.tokenPriceDai = aggregator.tokenPriceDai();

            if (cancelReason == CancelReason.NONE) {
                v.profitP = currentPercentProfit(t.openPrice, a.price, t.buy, t.leverage);
                v.posDai = v.levPosDai / t.leverage;

                v.daiSentToTrader = unregisterTrade(
                    t,
                    true,
                    v.profitP,
                    v.posDai,
                    i.openInterestDai,
                    (v.levPosDai * aggregator.pairsStorage().pairCloseFeeP(t.pairIndex)) / 100 / PRECISION,
                    (v.levPosDai * aggregator.pairsStorage().pairNftLimitOrderFeeP(t.pairIndex)) / 100 / PRECISION
                );

                emit MarketExecuted(a.orderId, t, false, a.price, 0, v.posDai, v.profitP, v.daiSentToTrader);
            } else {
                // Dev / gov rewards to pay for oracle cost
                // Charge in DAI if collateral in storage or token if collateral in vault
                v.reward1 = t.positionSizeDai > 0
                    ? storageT.handleDevGovFees(t.pairIndex, v.levPosDai, true, true)
                    : (storageT.handleDevGovFees(
                        t.pairIndex,
                        (v.levPosDai * PRECISION) / v.tokenPriceDai,
                        false,
                        true
                    ) * v.tokenPriceDai) / PRECISION;

                t.initialPosToken -= (v.reward1 * PRECISION) / i.tokenPriceDai;
                storageT.updateTrade(t);

                emit DevGovFeeCharged(t.trader, v.reward1);
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit MarketCloseCanceled(a.orderId, o.trade.trader, o.trade.pairIndex, o.trade.index, cancelReason);
        }

        storageT.unregisterPendingMarketOrder(a.orderId, false);
    }

    function executeNftOpenOrderCallback(AggregatorAnswer memory a) external onlyPriceAggregator notDone {
        (uint open, uint high, uint low) = (a.open, a.high, a.low);

        StorageInterfaceV5.PendingNftOrder memory n = storageT.reqID_pendingNftOrder(a.orderId);

        CancelReason cancelReason = !storageT.hasOpenLimitOrder(n.trader, n.pairIndex, n.index)
            ? CancelReason.NO_TRADE
            : CancelReason.NONE;

        if (cancelReason == CancelReason.NONE) {
            StorageInterfaceV5.OpenLimitOrder memory o = storageT.getOpenLimitOrder(n.trader, n.pairIndex, n.index);

            NftRewardsInterfaceV6_3_1.OpenLimitOrderType t = nftRewards.openLimitOrderTypes(
                n.trader,
                n.pairIndex,
                n.index
            );

            // Note: o.minPrice always equals o.maxPrice so can use either
            (uint priceImpactP, uint priceAfterImpact, CancelReason _cancelReason) = _openTradePrep(
                OpenTradePrepInput(
                    o.maxPrice,
                    o.maxPrice,
                    open,
                    a.spreadP,
                    o.spreadReductionP,
                    o.buy,
                    o.pairIndex,
                    o.positionSize,
                    o.leverage,
                    tradeData[o.trader][o.pairIndex][o.index][TradeType.LIMIT].maxSlippageP,
                    o.tp,
                    o.sl
                )
            );

            bool exactExecution = (high >= o.maxPrice && low <= o.maxPrice);

            cancelReason = !exactExecution &&
                (
                    o.maxPrice == 0 || t == NftRewardsInterfaceV6_3_1.OpenLimitOrderType.MOMENTUM
                        ? (o.buy ? open < o.maxPrice : open > o.maxPrice)
                        : (o.buy ? open > o.maxPrice : open < o.maxPrice)
                )
                ? CancelReason.NOT_HIT
                : _cancelReason;

            if (cancelReason == CancelReason.NONE) {
                (StorageInterfaceV5.Trade memory finalTrade, uint tokenPriceDai) = registerTrade(
                    StorageInterfaceV5.Trade(
                        o.trader,
                        o.pairIndex,
                        0,
                        0,
                        o.positionSize,
                        priceAfterImpact,
                        o.buy,
                        o.leverage,
                        o.tp,
                        o.sl
                    ),
                    n.nftId,
                    n.index
                );

                storageT.unregisterOpenLimitOrder(o.trader, o.pairIndex, o.index);

                emit LimitExecuted(
                    a.orderId,
                    n.index,
                    finalTrade,
                    n.nftHolder,
                    StorageInterfaceV5.LimitOrder.OPEN,
                    finalTrade.openPrice,
                    priceImpactP,
                    (finalTrade.initialPosToken * tokenPriceDai) / PRECISION,
                    0,
                    0,
                    exactExecution
                );
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit NftOrderCanceled(a.orderId, n.nftHolder, StorageInterfaceV5.LimitOrder.OPEN, cancelReason);
        }

        nftRewards.unregisterTrigger(
            NftRewardsInterfaceV6_3_1.TriggeredLimitId(n.trader, n.pairIndex, n.index, n.orderType)
        );

        storageT.unregisterPendingNftOrder(a.orderId);
    }

    function executeNftCloseOrderCallback(AggregatorAnswer memory a) external onlyPriceAggregator notDone {
        (uint open, uint high, uint low) = (a.open, a.high, a.low);

        StorageInterfaceV5.PendingNftOrder memory o = storageT.reqID_pendingNftOrder(a.orderId);
        NftRewardsInterfaceV6_3_1.TriggeredLimitId memory triggeredLimitId = NftRewardsInterfaceV6_3_1.TriggeredLimitId(
            o.trader,
            o.pairIndex,
            o.index,
            o.orderType
        );
        StorageInterfaceV5.Trade memory t = getOpenTrade(o.trader, o.pairIndex, o.index);

        AggregatorInterfaceV6_4 aggregator = storageT.priceAggregator();

        CancelReason cancelReason = open == 0
            ? CancelReason.MARKET_CLOSED
            : (t.leverage == 0 ? CancelReason.NO_TRADE : CancelReason.NONE);

        if (cancelReason == CancelReason.NONE) {
            StorageInterfaceV5.TradeInfo memory i = getOpenTradeInfo(t.trader, t.pairIndex, t.index);

            PairsStorageInterfaceV6 pairsStored = aggregator.pairsStorage();

            Values memory v;
            v.levPosDai = (t.initialPosToken * i.tokenPriceDai * t.leverage) / PRECISION;
            v.posDai = v.levPosDai / t.leverage;

            if (o.orderType == StorageInterfaceV5.LimitOrder.LIQ) {
                v.liqPrice = borrowingFees.getTradeLiquidationPrice(
                    GNSBorrowingFeesInterfaceV6_4.LiqPriceInput(
                        t.trader,
                        t.pairIndex,
                        t.index,
                        t.openPrice,
                        t.buy,
                        v.posDai,
                        t.leverage
                    )
                );
            }

            v.price = o.orderType == StorageInterfaceV5.LimitOrder.TP
                ? t.tp
                : (o.orderType == StorageInterfaceV5.LimitOrder.SL ? t.sl : v.liqPrice);

            v.exactExecution = v.price > 0 && low <= v.price && high >= v.price;

            if (v.exactExecution) {
                v.reward1 = o.orderType == StorageInterfaceV5.LimitOrder.LIQ
                    ? (v.posDai * 5) / 100
                    : (v.levPosDai * pairsStored.pairNftLimitOrderFeeP(t.pairIndex)) / 100 / PRECISION;
            } else {
                v.price = open;

                v.reward1 = o.orderType == StorageInterfaceV5.LimitOrder.LIQ
                    ? ((t.buy ? open <= v.liqPrice : open >= v.liqPrice) ? (v.posDai * 5) / 100 : 0)
                    : (
                        ((o.orderType == StorageInterfaceV5.LimitOrder.TP &&
                            t.tp > 0 &&
                            (t.buy ? open >= t.tp : open <= t.tp)) ||
                            (o.orderType == StorageInterfaceV5.LimitOrder.SL &&
                                t.sl > 0 &&
                                (t.buy ? open <= t.sl : open >= t.sl)))
                            ? (v.levPosDai * pairsStored.pairNftLimitOrderFeeP(t.pairIndex)) / 100 / PRECISION
                            : 0
                    );
            }

            cancelReason = v.reward1 == 0 ? CancelReason.NOT_HIT : CancelReason.NONE;

            // If can be triggered
            if (cancelReason == CancelReason.NONE) {
                v.profitP = currentPercentProfit(t.openPrice, v.price, t.buy, t.leverage);
                v.tokenPriceDai = aggregator.tokenPriceDai();

                v.daiSentToTrader = unregisterTrade(
                    t,
                    false,
                    v.profitP,
                    v.posDai,
                    i.openInterestDai,
                    o.orderType == StorageInterfaceV5.LimitOrder.LIQ
                        ? v.reward1
                        : (v.levPosDai * pairsStored.pairCloseFeeP(t.pairIndex)) / 100 / PRECISION,
                    v.reward1
                );

                // Convert NFT bot fee from DAI to token value
                v.reward2 = (v.reward1 * PRECISION) / v.tokenPriceDai;

                nftRewards.distributeNftReward(triggeredLimitId, v.reward2, v.tokenPriceDai);

                storageT.increaseNftRewards(o.nftId, v.reward2);

                emit NftBotFeeCharged(t.trader, v.reward1);

                emit LimitExecuted(
                    a.orderId,
                    o.index,
                    t,
                    o.nftHolder,
                    o.orderType,
                    v.price,
                    0,
                    v.posDai,
                    v.profitP,
                    v.daiSentToTrader,
                    v.exactExecution
                );
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit NftOrderCanceled(a.orderId, o.nftHolder, o.orderType, cancelReason);
        }

        nftRewards.unregisterTrigger(triggeredLimitId);
        storageT.unregisterPendingNftOrder(a.orderId);
    }

    // Shared code between market & limit callbacks
    function registerTrade(
        StorageInterfaceV5.Trade memory trade,
        uint nftId,
        uint limitIndex
    ) private returns (StorageInterfaceV5.Trade memory, uint) {
        AggregatorInterfaceV6_4 aggregator = storageT.priceAggregator();
        PairsStorageInterfaceV6 pairsStored = aggregator.pairsStorage();

        Values memory v;

        v.levPosDai = trade.positionSizeDai * trade.leverage;
        v.tokenPriceDai = aggregator.tokenPriceDai();

        // 1. Charge referral fee (if applicable) and send DAI amount to vault
        if (referrals.getTraderReferrer(trade.trader) != address(0)) {
            // Use this variable to store lev pos dai for dev/gov fees after referral fees
            // and before volumeReferredDai increases
            v.posDai =
                (v.levPosDai * (100 * PRECISION - referrals.getPercentOfOpenFeeP(trade.trader))) /
                100 /
                PRECISION;

            v.reward1 = referrals.distributePotentialReward(
                trade.trader,
                v.levPosDai,
                pairsStored.pairOpenFeeP(trade.pairIndex),
                v.tokenPriceDai
            );

            sendToVault(v.reward1, trade.trader);
            trade.positionSizeDai -= v.reward1;

            emit ReferralFeeCharged(trade.trader, v.reward1);
        }

        // 2. Charge opening fee - referral fee (if applicable)
        v.reward2 = storageT.handleDevGovFees(trade.pairIndex, (v.posDai > 0 ? v.posDai : v.levPosDai), true, true);

        trade.positionSizeDai -= v.reward2;

        emit DevGovFeeCharged(trade.trader, v.reward2);

        // 3. Charge NFT / SSS fee
        v.reward2 = (v.levPosDai * pairsStored.pairNftLimitOrderFeeP(trade.pairIndex)) / 100 / PRECISION;
        trade.positionSizeDai -= v.reward2;

        // 3.1 Distribute NFT fee and send DAI amount to vault (if applicable)
        if (nftId < 1500) {
            sendToVault(v.reward2, trade.trader);

            // Convert NFT bot fee from DAI to token value
            v.reward3 = (v.reward2 * PRECISION) / v.tokenPriceDai;

            nftRewards.distributeNftReward(
                NftRewardsInterfaceV6_3_1.TriggeredLimitId(
                    trade.trader,
                    trade.pairIndex,
                    limitIndex,
                    StorageInterfaceV5.LimitOrder.OPEN
                ),
                v.reward3,
                v.tokenPriceDai
            );
            storageT.increaseNftRewards(nftId, v.reward3);

            emit NftBotFeeCharged(trade.trader, v.reward2);

            // 3.2 Distribute SSS fee (if applicable)
        } else {
            distributeStakingReward(trade.trader, v.reward2);
        }

        // 4. Set trade final details
        trade.index = storageT.firstEmptyTradeIndex(trade.trader, trade.pairIndex);
        trade.initialPosToken = (trade.positionSizeDai * PRECISION) / v.tokenPriceDai;

        trade.tp = correctTp(trade.openPrice, trade.leverage, trade.tp, trade.buy);
        trade.sl = correctSl(trade.openPrice, trade.leverage, trade.sl, trade.buy);

        // 5. Call other contracts
        pairInfos.storeTradeInitialAccFees(trade.trader, trade.pairIndex, trade.index, trade.buy);
        pairsStored.updateGroupCollateral(trade.pairIndex, trade.positionSizeDai, trade.buy, true);
        borrowingFees.handleTradeAction(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.positionSizeDai * trade.leverage,
            true,
            trade.buy
        );

        // 6. Store final trade in storage contract
        storageT.storeTrade(
            trade,
            StorageInterfaceV5.TradeInfo(0, v.tokenPriceDai, trade.positionSizeDai * trade.leverage, 0, 0, false)
        );

        // 7. Store tradeLastUpdated
        LastUpdated storage lastUpdated = tradeLastUpdated[trade.trader][trade.pairIndex][trade.index][
            TradeType.MARKET
        ];
        uint32 currBlock = uint32(ChainUtils.getBlockNumber());
        lastUpdated.tp = currBlock;
        lastUpdated.sl = currBlock;
        lastUpdated.created = currBlock;

        return (trade, v.tokenPriceDai);
    }

    function unregisterTrade(
        StorageInterfaceV5.Trade memory trade,
        bool marketOrder,
        int percentProfit, // PRECISION
        uint currentDaiPos, // 1e18
        uint openInterestDai, // 1e18
        uint closingFeeDai, // 1e18
        uint nftFeeDai // 1e18 (= SSS reward if market order)
    ) private returns (uint daiSentToTrader) {
        IGToken vault = storageT.vault();

        // 1. Calculate net PnL (after all closing and holding fees)
        (daiSentToTrader, ) = _getTradeValue(trade, currentDaiPos, percentProfit, closingFeeDai + nftFeeDai);

        // 2. Calls to other contracts
        borrowingFees.handleTradeAction(trade.trader, trade.pairIndex, trade.index, openInterestDai, false, trade.buy);
        getPairsStorage().updateGroupCollateral(trade.pairIndex, openInterestDai / trade.leverage, trade.buy, false);

        // 3. Unregister trade from storage
        storageT.unregisterTrade(trade.trader, trade.pairIndex, trade.index);

        // 4.1 If collateral in storage (opened after update)
        if (trade.positionSizeDai > 0) {
            Values memory v;

            // 4.1.1 DAI vault reward
            v.reward2 = (closingFeeDai * daiVaultFeeP) / 100;
            transferFromStorageToAddress(address(this), v.reward2);
            vault.distributeReward(v.reward2);

            emit DaiVaultFeeCharged(trade.trader, v.reward2);

            // 4.1.2 SSS reward
            v.reward3 = marketOrder ? nftFeeDai + (closingFeeDai * sssFeeP) / 100 : (closingFeeDai * sssFeeP) / 100;

            distributeStakingReward(trade.trader, v.reward3);

            // 4.1.3 Take DAI from vault if winning trade
            // or send DAI to vault if losing trade
            uint daiLeftInStorage = currentDaiPos - v.reward3 - v.reward2;

            if (daiSentToTrader > daiLeftInStorage) {
                vault.sendAssets(daiSentToTrader - daiLeftInStorage, trade.trader);
                transferFromStorageToAddress(trade.trader, daiLeftInStorage);
            } else {
                sendToVault(daiLeftInStorage - daiSentToTrader, trade.trader);
                transferFromStorageToAddress(trade.trader, daiSentToTrader);
            }

            // 4.2 If collateral in vault (opened before update)
        } else {
            vault.sendAssets(daiSentToTrader, trade.trader);
        }
    }

    // Utils (external)
    function setTradeLastUpdated(SimplifiedTradeId calldata _id, LastUpdated memory _lastUpdated) external onlyTrading {
        tradeLastUpdated[_id.trader][_id.pairIndex][_id.index][_id.tradeType] = _lastUpdated;
    }

    function setTradeData(SimplifiedTradeId calldata _id, TradeData memory _tradeData) external onlyTrading {
        tradeData[_id.trader][_id.pairIndex][_id.index][_id.tradeType] = _tradeData;
    }

    // Utils (getters)
    function _getTradeValue(
        StorageInterfaceV5.Trade memory trade,
        uint currentDaiPos, // 1e18
        int percentProfit, // PRECISION
        uint closingFees // 1e18
    ) private returns (uint value, uint borrowingFee) {
        int netProfitP;

        (netProfitP, borrowingFee) = _getBorrowingFeeAdjustedPercentProfit(trade, currentDaiPos, percentProfit);
        value = pairInfos.getTradeValue(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy,
            currentDaiPos,
            trade.leverage,
            netProfitP,
            closingFees
        );

        emit BorrowingFeeCharged(trade.trader, value, borrowingFee);
    }

    function _getBorrowingFeeAdjustedPercentProfit(
        StorageInterfaceV5.Trade memory trade,
        uint currentDaiPos, // 1e18
        int percentProfit // PRECISION
    ) private view returns (int netProfitP, uint borrowingFee) {
        borrowingFee = borrowingFees.getTradeBorrowingFee(
            GNSBorrowingFeesInterfaceV6_4.BorrowingFeeInput(
                trade.trader,
                trade.pairIndex,
                trade.index,
                trade.buy,
                currentDaiPos,
                trade.leverage
            )
        );
        netProfitP = percentProfit - int((borrowingFee * 100 * PRECISION) / currentDaiPos);
    }

    function withinMaxLeverage(uint pairIndex, uint leverage) private view returns (bool) {
        uint pairMaxLev = pairMaxLeverage[pairIndex];
        return pairMaxLev == 0 ? leverage <= getPairsStorage().pairMaxLeverage(pairIndex) : leverage <= pairMaxLev;
    }

    function withinExposureLimits(
        uint pairIndex,
        bool buy,
        uint positionSizeDai,
        uint leverage
    ) private view returns (bool) {
        uint levPositionSizeDai = positionSizeDai * leverage;

        return
            storageT.openInterestDai(pairIndex, buy ? 0 : 1) + levPositionSizeDai <=
            borrowingFees.getPairMaxOi(pairIndex) * 1e8 &&
            borrowingFees.withinMaxGroupOi(pairIndex, buy, levPositionSizeDai);
    }

    function currentPercentProfit(
        uint openPrice,
        uint currentPrice,
        bool buy,
        uint leverage
    ) private pure returns (int p) {
        int maxPnlP = int(MAX_GAIN_P) * int(PRECISION);

        p = openPrice > 0
            ? ((buy ? int(currentPrice) - int(openPrice) : int(openPrice) - int(currentPrice)) *
                100 *
                int(PRECISION) *
                int(leverage)) / int(openPrice)
            : int(0);

        p = p > maxPnlP ? maxPnlP : p;
    }

    function correctTp(uint openPrice, uint leverage, uint tp, bool buy) private pure returns (uint) {
        if (tp == 0 || currentPercentProfit(openPrice, tp, buy, leverage) == int(MAX_GAIN_P) * int(PRECISION)) {
            uint tpDiff = (openPrice * MAX_GAIN_P) / leverage / 100;

            return buy ? openPrice + tpDiff : (tpDiff <= openPrice ? openPrice - tpDiff : 0);
        }

        return tp;
    }

    function correctSl(uint openPrice, uint leverage, uint sl, bool buy) private pure returns (uint) {
        if (sl > 0 && currentPercentProfit(openPrice, sl, buy, leverage) < int(MAX_SL_P) * int(PRECISION) * -1) {
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
    ) private pure returns (uint) {
        uint priceDiff = (price * (spreadP - (spreadP * spreadReductionP) / 100)) / 100 / PRECISION;

        return long ? price + priceDiff : price - priceDiff;
    }

    function _openTradePrep(
        OpenTradePrepInput memory c
    ) private view returns (uint priceImpactP, uint priceAfterImpact, CancelReason cancelReason) {
        (priceImpactP, priceAfterImpact) = pairInfos.getTradePriceImpact(
            marketExecutionPrice(c.executionPrice, c.spreadP, c.spreadReductionP, c.buy),
            c.pairIndex,
            c.buy,
            c.positionSize * c.leverage
        );

        uint maxSlippage = c.maxSlippageP > 0
            ? (c.wantedPrice * c.maxSlippageP) / 100 / PRECISION
            : c.wantedPrice / 100; // 1% by default

        cancelReason = isPaused
            ? CancelReason.PAUSED
            : (
                c.marketPrice == 0
                    ? CancelReason.MARKET_CLOSED
                    : (
                        c.buy
                            ? priceAfterImpact > c.wantedPrice + maxSlippage
                            : priceAfterImpact < c.wantedPrice - maxSlippage
                    )
                    ? CancelReason.SLIPPAGE
                    : (c.tp > 0 && (c.buy ? priceAfterImpact >= c.tp : priceAfterImpact <= c.tp))
                    ? CancelReason.TP_REACHED
                    : (c.sl > 0 && (c.buy ? priceAfterImpact <= c.sl : priceAfterImpact >= c.sl))
                    ? CancelReason.SL_REACHED
                    : !withinExposureLimits(c.pairIndex, c.buy, c.positionSize, c.leverage)
                    ? CancelReason.EXPOSURE_LIMITS
                    : priceImpactP * c.leverage > pairInfos.maxNegativePnlOnOpenP()
                    ? CancelReason.PRICE_IMPACT
                    : !withinMaxLeverage(c.pairIndex, c.leverage)
                    ? CancelReason.MAX_LEVERAGE
                    : CancelReason.NONE
            );
    }

    function getPendingMarketOrder(uint orderId) private view returns (StorageInterfaceV5.PendingMarketOrder memory) {
        return storageT.reqID_pendingMarketOrder(orderId);
    }

    function getPairsStorage() private view returns (PairsStorageInterfaceV6) {
        return storageT.priceAggregator().pairsStorage();
    }

    function getOpenTrade(
        address trader,
        uint pairIndex,
        uint index
    ) private view returns (StorageInterfaceV5.Trade memory) {
        return storageT.openTrades(trader, pairIndex, index);
    }

    function getOpenTradeInfo(
        address trader,
        uint pairIndex,
        uint index
    ) private view returns (StorageInterfaceV5.TradeInfo memory) {
        return storageT.openTradesInfo(trader, pairIndex, index);
    }

    // Utils (private)
    function distributeStakingReward(address trader, uint amountDai) private {
        transferFromStorageToAddress(address(this), amountDai);
        staking.distributeRewardDai(amountDai);
        emit SssFeeCharged(trader, amountDai);
    }

    function sendToVault(uint amountDai, address trader) private {
        transferFromStorageToAddress(address(this), amountDai);
        storageT.vault().receiveAssets(amountDai, trader);
    }

    function transferFromStorageToAddress(address to, uint amountDai) private {
        storageT.transferDai(address(storageT), to, amountDai);
    }

    // Public views
    function getAllPairsMaxLeverage() external view returns (uint[] memory) {
        uint len = getPairsStorage().pairsCount();
        uint[] memory lev = new uint[](len);

        for (uint i; i < len; ) {
            lev[i] = pairMaxLeverage[i];
            unchecked {
                ++i;
            }
        }

        return lev;
    }
}

