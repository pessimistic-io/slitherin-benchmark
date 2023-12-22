// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Initializable} from "./Initializable.sol";

import "./IGNSTradingCallbacks.sol";
import "./IGNSPairInfos.sol";
import "./IGNSReferrals.sol";
import "./IGToken.sol";
import "./IGNSStaking.sol";
import "./IGNSBorrowingFees.sol";
import "./IGNSOracleRewards.sol";
import "./IERC20.sol";

import "./ChainUtils.sol";

/**
 * @custom:version 6.4.2
 */
contract GNSTradingCallbacks is Initializable, IGNSTradingCallbacks {
    // Contracts (constant)
    IGNSTradingStorage public storageT;
    IGNSOracleRewards public nftRewards;
    IGNSPairInfos public pairInfos;
    IGNSReferrals public referrals;
    IGNSStaking public staking;

    // Params (constant)
    uint256 private constant PRECISION = 1e10; // 10 decimals
    uint256 private constant MAX_SL_P = 75; // -75% PNL
    uint256 private constant MAX_GAIN_P = 900; // 900% PnL (10x)
    uint256 private constant MAX_EXECUTE_TIMEOUT = 5; // 5 blocks

    // Params (adjustable)
    uint256 public daiVaultFeeP; // % of closing fee going to DAI vault (eg. 40)
    uint256 public lpFeeP; // % of closing fee going to GNS/DAI LPs (eg. 20)
    uint256 public sssFeeP; // % of closing fee going to GNS staking (eg. 40)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract
    uint256 public canExecuteTimeout; // How long an update to TP/SL/Limit has to wait before it is executable (DEPRECATED)

    // Last Updated State
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(TradeType => LastUpdated))))
        public tradeLastUpdated; // Block numbers for last updated

    // v6.3.2 Storage/State
    IGNSBorrowingFees public borrowingFees;
    mapping(uint256 => uint256) public pairMaxLeverage;

    // v6.4 Storage
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(TradeType => TradeData)))) public tradeData; // More storage for trades / limit orders

    // v6.4.1 State
    uint256 public govFeesDai; // 1e18

    // Custom errors (save gas)
    error WrongParams();
    error Forbidden();

    function initialize(
        IGNSTradingStorage _storageT,
        IGNSOracleRewards _nftRewards,
        IGNSPairInfos _pairInfos,
        IGNSReferrals _referrals,
        IGNSStaking _staking,
        address vaultToApprove,
        uint256 _daiVaultFeeP,
        uint256 _lpFeeP,
        uint256 _sssFeeP,
        uint256 _canExecuteTimeout
    ) external initializer {
        if (
            !(address(_storageT) != address(0) &&
                address(_nftRewards) != address(0) &&
                address(_pairInfos) != address(0) &&
                address(_referrals) != address(0) &&
                address(_staking) != address(0) &&
                vaultToApprove != address(0) &&
                _daiVaultFeeP + _lpFeeP + _sssFeeP == 100 &&
                _canExecuteTimeout <= MAX_EXECUTE_TIMEOUT)
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

        IERC20 t = IERC20(storageT.dai());
        t.approve(address(staking), type(uint256).max);
        t.approve(vaultToApprove, type(uint256).max);
    }

    function initializeV2(IGNSBorrowingFees _borrowingFees) external reinitializer(2) {
        if (address(_borrowingFees) == address(0)) {
            revert WrongParams();
        }
        borrowingFees = _borrowingFees;
    }

    // skip v3 to be synced with testnet
    function initializeV4(IGNSStaking _staking, IGNSOracleRewards _oracleRewards) external reinitializer(4) {
        if (!(address(_staking) != address(0) && address(_oracleRewards) != address(0))) {
            revert WrongParams();
        }

        IERC20 t = IERC20(storageT.dai());
        t.approve(address(staking), 0); // revoke old staking contract
        t.approve(address(_staking), type(uint256).max); // approve new staking contract

        staking = _staking;
        nftRewards = _oracleRewards;
    }

    // Modifiers
    modifier onlyGov() {
        _isGov();
        _;
    }
    modifier onlyPriceAggregator() {
        _isPriceAggregator();
        _;
    }
    modifier notDone() {
        _isNotDone();
        _;
    }
    modifier onlyTrading() {
        _isTrading();
        _;
    }
    modifier onlyManager() {
        _isManager();
        _;
    }

    // Saving code size by calling these functions inside modifiers
    function _isGov() private view {
        if (msg.sender != storageT.gov()) {
            revert Forbidden();
        }
    }

    function _isPriceAggregator() private view {
        if (msg.sender != address(storageT.priceAggregator())) {
            revert Forbidden();
        }
    }

    function _isNotDone() private view {
        if (isDone) {
            revert Forbidden();
        }
    }

    function _isTrading() private view {
        if (msg.sender != storageT.trading()) {
            revert Forbidden();
        }
    }

    function _isManager() private view {
        if (msg.sender != pairInfos.manager()) {
            revert Forbidden();
        }
    }

    // Manage params
    function setPairMaxLeverage(uint256 pairIndex, uint256 maxLeverage) external onlyManager {
        _setPairMaxLeverage(pairIndex, maxLeverage);
    }

    function setPairMaxLeverageArray(uint256[] calldata indices, uint256[] calldata values) external onlyManager {
        uint256 len = indices.length;

        if (len != values.length) {
            revert WrongParams();
        }

        for (uint256 i; i < len; ) {
            _setPairMaxLeverage(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setPairMaxLeverage(uint256 pairIndex, uint256 maxLeverage) private {
        pairMaxLeverage[pairIndex] = maxLeverage;
        emit PairMaxLeverageUpdated(pairIndex, maxLeverage);
    }

    function setClosingFeeSharesP(uint256 _daiVaultFeeP, uint256 _lpFeeP, uint256 _sssFeeP) external onlyGov {
        if (_daiVaultFeeP + _lpFeeP + _sssFeeP != 100) {
            revert WrongParams();
        }

        daiVaultFeeP = _daiVaultFeeP;
        lpFeeP = _lpFeeP;
        sssFeeP = _sssFeeP;

        emit ClosingFeeSharesPUpdated(_daiVaultFeeP, _lpFeeP, _sssFeeP);
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

    // Claim fees
    function claimGovFees() external onlyGov {
        uint256 valueDai = govFeesDai;
        govFeesDai = 0;

        _transferFromStorageToAddress(storageT.gov(), valueDai);

        emit GovFeesClaimed(valueDai);
    }

    // Callbacks
    function openTradeMarketCallback(AggregatorAnswer memory a) external onlyPriceAggregator notDone {
        IGNSTradingStorage.PendingMarketOrder memory o = _getPendingMarketOrder(a.orderId);

        if (o.block == 0) {
            return;
        }

        IGNSTradingStorage.Trade memory t = o.trade;

        (uint256 priceImpactP, uint256 priceAfterImpact, CancelReason cancelReason) = _openTradePrep(
            OpenTradePrepInput(
                a.price,
                o.wantedPrice,
                a.price,
                a.spreadP,
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
            (IGNSTradingStorage.Trade memory finalTrade, uint256 tokenPriceDai) = _registerTrade(t, false, 0);

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
            // Gov fee to pay for oracle cost
            uint256 govFees = _handleGovFees(t.trader, t.pairIndex, t.positionSizeDai * t.leverage, true);
            _transferFromStorageToAddress(t.trader, t.positionSizeDai - govFees);

            emit MarketOpenCanceled(a.orderId, t.trader, t.pairIndex, cancelReason);
        }

        storageT.unregisterPendingMarketOrder(a.orderId, true);
    }

    function closeTradeMarketCallback(AggregatorAnswer memory a) external onlyPriceAggregator notDone {
        IGNSTradingStorage.PendingMarketOrder memory o = _getPendingMarketOrder(a.orderId);

        if (o.block == 0) {
            return;
        }

        IGNSTradingStorage.Trade memory t = _getOpenTrade(o.trade.trader, o.trade.pairIndex, o.trade.index);

        CancelReason cancelReason = t.leverage == 0
            ? CancelReason.NO_TRADE
            : (a.price == 0 ? CancelReason.MARKET_CLOSED : CancelReason.NONE);

        if (cancelReason != CancelReason.NO_TRADE) {
            IGNSTradingStorage.TradeInfo memory i = _getOpenTradeInfo(t.trader, t.pairIndex, t.index);
            IGNSPriceAggregator aggregator = storageT.priceAggregator();

            Values memory v;
            v.levPosDai = (t.initialPosToken * i.tokenPriceDai * t.leverage) / PRECISION;
            v.tokenPriceDai = aggregator.tokenPriceDai();

            if (cancelReason == CancelReason.NONE) {
                v.profitP = _currentPercentProfit(t.openPrice, a.price, t.buy, t.leverage);
                v.posDai = v.levPosDai / t.leverage;

                v.daiSentToTrader = _unregisterTrade(
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
                // Gov fee to pay for oracle cost
                uint256 govFee = _handleGovFees(t.trader, t.pairIndex, v.levPosDai, t.positionSizeDai > 0);
                t.initialPosToken -= (govFee * PRECISION) / i.tokenPriceDai;

                storageT.updateTrade(t);
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit MarketCloseCanceled(a.orderId, o.trade.trader, o.trade.pairIndex, o.trade.index, cancelReason);
        }

        storageT.unregisterPendingMarketOrder(a.orderId, false);
    }

    function executeNftOpenOrderCallback(AggregatorAnswer memory a) external onlyPriceAggregator notDone {
        IGNSTradingStorage.PendingNftOrder memory n = storageT.reqID_pendingNftOrder(a.orderId);

        CancelReason cancelReason = !storageT.hasOpenLimitOrder(n.trader, n.pairIndex, n.index)
            ? CancelReason.NO_TRADE
            : CancelReason.NONE;

        if (cancelReason == CancelReason.NONE) {
            IGNSTradingStorage.OpenLimitOrder memory o = storageT.getOpenLimitOrder(n.trader, n.pairIndex, n.index);

            IGNSOracleRewards.OpenLimitOrderType t = nftRewards.openLimitOrderTypes(n.trader, n.pairIndex, n.index);

            cancelReason = (a.high >= o.maxPrice && a.low <= o.maxPrice) ? CancelReason.NONE : CancelReason.NOT_HIT;

            // Note: o.minPrice always equals o.maxPrice so can use either
            (uint256 priceImpactP, uint256 priceAfterImpact, CancelReason _cancelReason) = _openTradePrep(
                OpenTradePrepInput(
                    cancelReason == CancelReason.NONE ? o.maxPrice : a.open,
                    o.maxPrice,
                    a.open,
                    a.spreadP,
                    o.buy,
                    o.pairIndex,
                    o.positionSize,
                    o.leverage,
                    tradeData[o.trader][o.pairIndex][o.index][TradeType.LIMIT].maxSlippageP,
                    o.tp,
                    o.sl
                )
            );

            bool exactExecution = cancelReason == CancelReason.NONE;

            cancelReason = !exactExecution &&
                (
                    o.maxPrice == 0 || t == IGNSOracleRewards.OpenLimitOrderType.MOMENTUM
                        ? (o.buy ? a.open < o.maxPrice : a.open > o.maxPrice)
                        : (o.buy ? a.open > o.maxPrice : a.open < o.maxPrice)
                )
                ? CancelReason.NOT_HIT
                : _cancelReason;

            if (cancelReason == CancelReason.NONE) {
                (IGNSTradingStorage.Trade memory finalTrade, uint256 tokenPriceDai) = _registerTrade(
                    IGNSTradingStorage.Trade(
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
                    true,
                    n.index
                );

                storageT.unregisterOpenLimitOrder(o.trader, o.pairIndex, o.index);

                emit LimitExecuted(
                    a.orderId,
                    n.index,
                    finalTrade,
                    n.nftHolder,
                    IGNSTradingStorage.LimitOrder.OPEN,
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
            emit NftOrderCanceled(a.orderId, n.nftHolder, IGNSTradingStorage.LimitOrder.OPEN, cancelReason);
        }

        nftRewards.unregisterTrigger(IGNSOracleRewards.TriggeredLimitId(n.trader, n.pairIndex, n.index, n.orderType));

        storageT.unregisterPendingNftOrder(a.orderId);
    }

    function executeNftCloseOrderCallback(AggregatorAnswer memory a) external onlyPriceAggregator notDone {
        IGNSTradingStorage.PendingNftOrder memory o = storageT.reqID_pendingNftOrder(a.orderId);
        IGNSOracleRewards.TriggeredLimitId memory triggeredLimitId = IGNSOracleRewards.TriggeredLimitId(
            o.trader,
            o.pairIndex,
            o.index,
            o.orderType
        );
        IGNSTradingStorage.Trade memory t = _getOpenTrade(o.trader, o.pairIndex, o.index);

        IGNSPriceAggregator aggregator = storageT.priceAggregator();

        CancelReason cancelReason = a.open == 0
            ? CancelReason.MARKET_CLOSED
            : (t.leverage == 0 ? CancelReason.NO_TRADE : CancelReason.NONE);

        if (cancelReason == CancelReason.NONE) {
            IGNSTradingStorage.TradeInfo memory i = _getOpenTradeInfo(t.trader, t.pairIndex, t.index);

            IGNSPairsStorage pairsStored = aggregator.pairsStorage();

            Values memory v;
            v.levPosDai = (t.initialPosToken * i.tokenPriceDai * t.leverage) / PRECISION;
            v.posDai = v.levPosDai / t.leverage;

            if (o.orderType == IGNSTradingStorage.LimitOrder.LIQ) {
                v.liqPrice = borrowingFees.getTradeLiquidationPrice(
                    IGNSBorrowingFees.LiqPriceInput(
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

            v.price = o.orderType == IGNSTradingStorage.LimitOrder.TP
                ? t.tp
                : (o.orderType == IGNSTradingStorage.LimitOrder.SL ? t.sl : v.liqPrice);

            v.exactExecution = v.price > 0 && a.low <= v.price && a.high >= v.price;

            if (v.exactExecution) {
                v.reward1 = o.orderType == IGNSTradingStorage.LimitOrder.LIQ
                    ? (v.posDai * 5) / 100
                    : (v.levPosDai * pairsStored.pairNftLimitOrderFeeP(t.pairIndex)) / 100 / PRECISION;
            } else {
                v.price = a.open;

                v.reward1 = o.orderType == IGNSTradingStorage.LimitOrder.LIQ
                    ? ((t.buy ? a.open <= v.liqPrice : a.open >= v.liqPrice) ? (v.posDai * 5) / 100 : 0)
                    : (
                        ((o.orderType == IGNSTradingStorage.LimitOrder.TP &&
                            t.tp > 0 &&
                            (t.buy ? a.open >= t.tp : a.open <= t.tp)) ||
                            (o.orderType == IGNSTradingStorage.LimitOrder.SL &&
                                t.sl > 0 &&
                                (t.buy ? a.open <= t.sl : a.open >= t.sl)))
                            ? (v.levPosDai * pairsStored.pairNftLimitOrderFeeP(t.pairIndex)) / 100 / PRECISION
                            : 0
                    );
            }

            cancelReason = v.reward1 == 0 ? CancelReason.NOT_HIT : CancelReason.NONE;

            // If can be triggered
            if (cancelReason == CancelReason.NONE) {
                v.profitP = _currentPercentProfit(t.openPrice, v.price, t.buy, t.leverage);
                v.tokenPriceDai = aggregator.tokenPriceDai();

                v.daiSentToTrader = _unregisterTrade(
                    t,
                    false,
                    v.profitP,
                    v.posDai,
                    i.openInterestDai,
                    o.orderType == IGNSTradingStorage.LimitOrder.LIQ
                        ? v.reward1
                        : (v.levPosDai * pairsStored.pairCloseFeeP(t.pairIndex)) / 100 / PRECISION,
                    v.reward1
                );

                _handleOracleRewards(triggeredLimitId, t.trader, (v.reward1 * 2) / 10, v.tokenPriceDai);

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
    function _registerTrade(
        IGNSTradingStorage.Trade memory trade,
        bool isLimitOrder,
        uint256 limitIndex
    ) private returns (IGNSTradingStorage.Trade memory, uint256) {
        IGNSPriceAggregator aggregator = storageT.priceAggregator();
        IGNSPairsStorage pairsStored = aggregator.pairsStorage();

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

            _sendToVault(v.reward1, trade.trader);
            trade.positionSizeDai -= v.reward1;

            emit ReferralFeeCharged(trade.trader, v.reward1);
        }

        // 2. Calculate gov fee (- referral fee if applicable)
        uint256 govFee = _handleGovFees(trade.trader, trade.pairIndex, (v.posDai > 0 ? v.posDai : v.levPosDai), true);
        v.reward1 = govFee; // SSS fee (previously dev fee)

        // 3. Calculate Market/Limit fee
        v.reward2 = (v.levPosDai * pairsStored.pairNftLimitOrderFeeP(trade.pairIndex)) / 100 / PRECISION;

        // 3.1 Deduct gov fee, SSS fee (previously dev fee), Market/Limit fee
        trade.positionSizeDai -= govFee + v.reward1 + v.reward2;

        // 3.2 Distribute Oracle fee and send DAI amount to vault if applicable
        if (isLimitOrder) {
            v.reward3 = (v.reward2 * 2) / 10; // 20% of limit fees
            _sendToVault(v.reward3, trade.trader);

            _handleOracleRewards(
                IGNSOracleRewards.TriggeredLimitId(
                    trade.trader,
                    trade.pairIndex,
                    limitIndex,
                    IGNSTradingStorage.LimitOrder.OPEN
                ),
                trade.trader,
                v.reward3,
                v.tokenPriceDai
            );
        }

        // 3.3 Distribute SSS fee (previous dev fee + market/limit fee - oracle reward)
        _distributeStakingReward(trade.trader, v.reward1 + v.reward2 - v.reward3);

        // 4. Set trade final details
        trade.index = storageT.firstEmptyTradeIndex(trade.trader, trade.pairIndex);
        trade.initialPosToken = (trade.positionSizeDai * PRECISION) / v.tokenPriceDai;

        trade.tp = _correctTp(trade.openPrice, trade.leverage, trade.tp, trade.buy);
        trade.sl = _correctSl(trade.openPrice, trade.leverage, trade.sl, trade.buy);

        // 5. Call other contracts
        v.levPosDai = trade.positionSizeDai * trade.leverage; // after fees now

        pairInfos.storeTradeInitialAccFees(trade.trader, trade.pairIndex, trade.index, trade.buy); // funding/rollover
        pairsStored.updateGroupCollateral(trade.pairIndex, trade.positionSizeDai, trade.buy, true); // pairsStorage group open collateral
        borrowingFees.handleTradeAction(trade.trader, trade.pairIndex, trade.index, v.levPosDai, true, trade.buy); // borrowing fees
        borrowingFees.addPriceImpactOpenInterest(v.levPosDai, trade.pairIndex, trade.buy); // price impact oi windows

        // 6. Store trade metadata
        tradeData[trade.trader][trade.pairIndex][trade.index][TradeType.MARKET] = TradeData(
            uint40(0),
            uint48(block.timestamp),
            0
        );
        LastUpdated storage lastUpdated = tradeLastUpdated[trade.trader][trade.pairIndex][trade.index][
            TradeType.MARKET
        ];
        uint32 currBlock = uint32(ChainUtils.getBlockNumber());
        lastUpdated.tp = currBlock;
        lastUpdated.sl = currBlock;
        lastUpdated.created = currBlock;

        // 7. Store final trade in storage contract
        storageT.storeTrade(trade, IGNSTradingStorage.TradeInfo(0, v.tokenPriceDai, v.levPosDai, 0, 0, false));

        return (trade, v.tokenPriceDai);
    }

    function _unregisterTrade(
        IGNSTradingStorage.Trade memory trade,
        bool marketOrder,
        int256 percentProfit, // PRECISION
        uint256 currentDaiPos, // 1e18
        uint256 openInterestDai, // 1e18
        uint256 closingFeeDai, // 1e18
        uint256 nftFeeDai // 1e18 (= SSS reward if market order)
    ) private returns (uint256 daiSentToTrader) {
        IGToken vault = IGToken(storageT.vault());

        // 1. Calculate net PnL (after all closing and holding fees)
        (daiSentToTrader, ) = _getTradeValue(trade, currentDaiPos, percentProfit, closingFeeDai + nftFeeDai);

        // 2. Call other contracts
        _getPairsStorage().updateGroupCollateral(trade.pairIndex, openInterestDai / trade.leverage, trade.buy, false); // pairsStorage group open collateral
        borrowingFees.handleTradeAction(trade.trader, trade.pairIndex, trade.index, openInterestDai, false, trade.buy); // borrowing fees
        borrowingFees.removePriceImpactOpenInterest( // price impact oi windows
                openInterestDai,
                trade.pairIndex,
                trade.buy,
                tradeData[trade.trader][trade.pairIndex][trade.index][TradeType.MARKET].lastOiUpdateTs
            );

        // 3. Unregister trade from storage
        storageT.unregisterTrade(trade.trader, trade.pairIndex, trade.index);

        // 4.1 If collateral in storage
        if (trade.positionSizeDai > 0) {
            Values memory v;

            // 5. DAI vault reward
            v.reward2 = (closingFeeDai * daiVaultFeeP) / 100;
            _transferFromStorageToAddress(address(this), v.reward2);
            vault.distributeReward(v.reward2);

            emit DaiVaultFeeCharged(trade.trader, v.reward2);

            // 6. SSS reward
            v.reward3 = (marketOrder ? nftFeeDai : (nftFeeDai * 8) / 10) + (closingFeeDai * sssFeeP) / 100;
            _distributeStakingReward(trade.trader, v.reward3);

            // 7. Take DAI from vault if winning trade
            // or send DAI to vault if losing trade
            uint256 daiLeftInStorage = currentDaiPos - v.reward3 - v.reward2;

            if (daiSentToTrader > daiLeftInStorage) {
                vault.sendAssets(daiSentToTrader - daiLeftInStorage, trade.trader);
                _transferFromStorageToAddress(trade.trader, daiLeftInStorage);
            } else {
                _sendToVault(daiLeftInStorage - daiSentToTrader, trade.trader);
                _transferFromStorageToAddress(trade.trader, daiSentToTrader);
            }

            // 4.2 If collateral in vault, just send dai to trader from vault
        } else {
            vault.sendAssets(daiSentToTrader, trade.trader);
        }
    }

    // Setters (external)
    function setTradeLastUpdated(SimplifiedTradeId calldata _id, LastUpdated memory _lastUpdated) external onlyTrading {
        tradeLastUpdated[_id.trader][_id.pairIndex][_id.index][_id.tradeType] = _lastUpdated;
    }

    function setTradeData(SimplifiedTradeId calldata _id, TradeData memory _tradeData) external onlyTrading {
        tradeData[_id.trader][_id.pairIndex][_id.index][_id.tradeType] = _tradeData;
    }

    // Getters (private)
    function _getTradeValue(
        IGNSTradingStorage.Trade memory trade,
        uint256 currentDaiPos, // 1e18
        int256 percentProfit, // PRECISION
        uint256 closingFees // 1e18
    ) private returns (uint256 value, uint256 borrowingFee) {
        int256 netProfitP;

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
        IGNSTradingStorage.Trade memory trade,
        uint256 currentDaiPos, // 1e18
        int256 percentProfit // PRECISION
    ) private view returns (int256 netProfitP, uint256 borrowingFee) {
        borrowingFee = borrowingFees.getTradeBorrowingFee(
            IGNSBorrowingFees.BorrowingFeeInput(
                trade.trader,
                trade.pairIndex,
                trade.index,
                trade.buy,
                currentDaiPos,
                trade.leverage
            )
        );
        netProfitP = percentProfit - int256((borrowingFee * 100 * PRECISION) / currentDaiPos);
    }

    function _withinMaxLeverage(uint256 pairIndex, uint256 leverage) private view returns (bool) {
        uint256 pairMaxLev = pairMaxLeverage[pairIndex];
        return pairMaxLev == 0 ? leverage <= _getPairsStorage().pairMaxLeverage(pairIndex) : leverage <= pairMaxLev;
    }

    function _withinExposureLimits(
        uint256 pairIndex,
        bool buy,
        uint256 positionSizeDai,
        uint256 leverage
    ) private view returns (bool) {
        uint256 levPositionSizeDai = positionSizeDai * leverage;

        return
            storageT.openInterestDai(pairIndex, buy ? 0 : 1) + levPositionSizeDai <=
            borrowingFees.getPairMaxOi(pairIndex) * 1e8 &&
            borrowingFees.withinMaxGroupOi(pairIndex, buy, levPositionSizeDai);
    }

    function _currentPercentProfit(
        uint256 openPrice,
        uint256 currentPrice,
        bool buy,
        uint256 leverage
    ) private pure returns (int256 p) {
        int256 maxPnlP = int256(MAX_GAIN_P) * int256(PRECISION);

        p = openPrice > 0
            ? ((buy ? int256(currentPrice) - int256(openPrice) : int256(openPrice) - int256(currentPrice)) *
                100 *
                int256(PRECISION) *
                int256(leverage)) / int256(openPrice)
            : int256(0);

        p = p > maxPnlP ? maxPnlP : p;
    }

    function _correctTp(uint256 openPrice, uint256 leverage, uint256 tp, bool buy) private pure returns (uint256) {
        if (tp == 0 || _currentPercentProfit(openPrice, tp, buy, leverage) == int256(MAX_GAIN_P) * int256(PRECISION)) {
            uint256 tpDiff = (openPrice * MAX_GAIN_P) / leverage / 100;

            return buy ? openPrice + tpDiff : (tpDiff <= openPrice ? openPrice - tpDiff : 0);
        }

        return tp;
    }

    function _correctSl(uint256 openPrice, uint256 leverage, uint256 sl, bool buy) private pure returns (uint256) {
        if (sl > 0 && _currentPercentProfit(openPrice, sl, buy, leverage) < int256(MAX_SL_P) * int256(PRECISION) * -1) {
            uint256 slDiff = (openPrice * MAX_SL_P) / leverage / 100;

            return buy ? openPrice - slDiff : openPrice + slDiff;
        }

        return sl;
    }

    function _marketExecutionPrice(uint256 price, uint256 spreadP, bool long) private pure returns (uint256) {
        uint256 priceDiff = (price * spreadP) / 100 / PRECISION;

        return long ? price + priceDiff : price - priceDiff;
    }

    function _openTradePrep(
        OpenTradePrepInput memory c
    ) private view returns (uint256 priceImpactP, uint256 priceAfterImpact, CancelReason cancelReason) {
        (priceImpactP, priceAfterImpact) = borrowingFees.getTradePriceImpact(
            _marketExecutionPrice(c.executionPrice, c.spreadP, c.buy),
            c.pairIndex,
            c.buy,
            c.positionSize * c.leverage
        );

        uint256 maxSlippage = c.maxSlippageP > 0
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
                    : !_withinExposureLimits(c.pairIndex, c.buy, c.positionSize, c.leverage)
                    ? CancelReason.EXPOSURE_LIMITS
                    : priceImpactP * c.leverage > pairInfos.maxNegativePnlOnOpenP()
                    ? CancelReason.PRICE_IMPACT
                    : !_withinMaxLeverage(c.pairIndex, c.leverage)
                    ? CancelReason.MAX_LEVERAGE
                    : CancelReason.NONE
            );
    }

    function _getPendingMarketOrder(
        uint256 orderId
    ) private view returns (IGNSTradingStorage.PendingMarketOrder memory) {
        return storageT.reqID_pendingMarketOrder(orderId);
    }

    function _getPairsStorage() private view returns (IGNSPairsStorage) {
        return storageT.priceAggregator().pairsStorage();
    }

    function _getOpenTrade(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) private view returns (IGNSTradingStorage.Trade memory) {
        return storageT.openTrades(trader, pairIndex, index);
    }

    function _getOpenTradeInfo(
        address trader,
        uint256 pairIndex,
        uint256 index
    ) private view returns (IGNSTradingStorage.TradeInfo memory) {
        return storageT.openTradesInfo(trader, pairIndex, index);
    }

    // Utils (private)
    function _distributeStakingReward(address trader, uint256 amountDai) private {
        _transferFromStorageToAddress(address(this), amountDai);
        staking.distributeRewardDai(amountDai);
        emit SssFeeCharged(trader, amountDai);
    }

    function _sendToVault(uint256 amountDai, address trader) private {
        _transferFromStorageToAddress(address(this), amountDai);
        IGToken(storageT.vault()).receiveAssets(amountDai, trader);
    }

    function _transferFromStorageToAddress(address to, uint256 amountDai) private {
        storageT.transferDai(address(storageT), to, amountDai);
    }

    function _handleOracleRewards(
        IGNSOracleRewards.TriggeredLimitId memory triggeredLimitId,
        address trader,
        uint256 oracleRewardDai,
        uint256 tokenPriceDai
    ) private {
        uint256 oracleRewardToken = ((oracleRewardDai * PRECISION) / tokenPriceDai);
        nftRewards.distributeOracleReward(triggeredLimitId, oracleRewardToken);

        emit TriggerFeeCharged(trader, oracleRewardDai);
    }

    function _handleGovFees(
        address trader,
        uint256 pairIndex,
        uint256 leveragedPositionSize,
        bool distribute
    ) private returns (uint256 govFee) {
        govFee = (leveragedPositionSize * storageT.priceAggregator().openFeeP(pairIndex)) / PRECISION / 100;

        if (distribute) {
            govFeesDai += govFee;
        }

        emit GovFeeCharged(trader, govFee, distribute);
    }

    // Getters (public)
    function getTradeLastUpdated(
        address trader,
        uint256 pairIndex,
        uint256 index,
        TradeType tradeType
    ) external view returns (LastUpdated memory) {
        return tradeLastUpdated[trader][pairIndex][index][tradeType];
    }

    function getAllPairsMaxLeverage() external view returns (uint256[] memory) {
        uint256 len = _getPairsStorage().pairsCount();
        uint256[] memory lev = new uint256[](len);

        for (uint256 i; i < len; ) {
            lev[i] = pairMaxLeverage[i];
            unchecked {
                ++i;
            }
        }

        return lev;
    }
}

