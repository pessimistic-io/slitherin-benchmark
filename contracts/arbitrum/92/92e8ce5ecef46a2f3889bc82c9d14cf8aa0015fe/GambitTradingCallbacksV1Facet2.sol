// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./IGambitTradingStorageV1.sol";
import "./IGambitPairInfosV1.sol";
import "./IGambitReferralsV1.sol";
import "./IGambitStakingV1.sol";

import "./IStableCoinDecimals.sol";

import "./GambitErrorsV1.sol";

import "./GambitTradingCallbacksV1Base.sol";

/**
 * @dev GambitTradingCallbacksV1Facet2 implements executeNftOpenOrderCallback, executeNftCloseOrderCallback, updateSlCallback, removeCollateralCallback
 */
abstract contract GambitTradingCallbacksV1Facet2 is
    GambitTradingCallbacksV1Base
{
    constructor() {
        _disableInitializers();
    }

    function executeNftOpenOrderCallback(
        AggregatorAnswer memory a
    ) external onlyPriceAggregator notDone {
        IGambitTradingStorageV1.PendingNftOrder memory n = storageT
            .reqID_pendingNftOrder(a.orderId);

        if (
            !isPaused &&
            !PausableInterfaceV5(storageT.trading()).isPaused() &&
            a.price > 0 &&
            storageT.hasOpenLimitOrder(n.trader, n.pairIndex, n.index)
            // disable checking timelock
            // && block.number >= storageT.nftLastSuccess(n.nftId) + storageT.nftSuccessTimelock()
        ) {
            IGambitTradingStorageV1.OpenLimitOrder memory o = storageT
                .getOpenLimitOrder(n.trader, n.pairIndex, n.index);

            NftRewardsInterfaceV6.OpenLimitOrderType t = nftRewards
                .openLimitOrderTypes(n.trader, n.pairIndex, n.index);

            (uint priceImpactP, uint priceAfterImpact) = pairInfos
                .getTradePriceImpact(
                    marketExecutionPrice(
                        t == NftRewardsInterfaceV6.OpenLimitOrderType.REVERSAL
                            ? o.maxPrice // o.minPrice = o.maxPrice in that case
                            : a.price,
                        a.conf,
                        a.confMultiplierP,
                        o.spreadReductionP,
                        o.buy
                    ),
                    o.pairIndex,
                    o.buy,
                    (o.positionSize * o.leverage) / 1e18
                );

            if (
                (
                    t == NftRewardsInterfaceV6.OpenLimitOrderType.LEGACY
                        ? (a.price >= o.minPrice && a.price <= o.maxPrice)
                        : t == NftRewardsInterfaceV6.OpenLimitOrderType.REVERSAL
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
                pairInfos.isWithinExposureLimits(
                    IGambitPairInfosV1.ExposureCalcParamsStruct({
                        pairIndex: o.pairIndex,
                        buy: o.buy,
                        positionSizeUsdc: o.positionSize,
                        leverage: o.leverage,
                        currentPrice: a.price,
                        openPrice: priceAfterImpact
                    })
                ) &&
                (priceImpactP * o.leverage) / 1e18 <=
                pairInfos.maxNegativePnlOnOpenP()
            ) {
                (
                    IGambitTradingStorageV1.Trade memory finalTrade,
                    uint tokenPriceUsdc
                ) = registerTrade(
                        IGambitTradingStorageV1.Trade({
                            trader: o.trader,
                            pairIndex: o.pairIndex,
                            index: 0,
                            initialPosToken: 0,
                            positionSizeUsdc: o.positionSize,
                            openPrice: priceAfterImpact,
                            buy: o.buy,
                            leverage: o.leverage,
                            tp: o.tp,
                            sl: o.sl
                        }),
                        n.nftId,
                        n.index
                    );

                storageT.unregisterOpenLimitOrder(
                    o.trader,
                    o.pairIndex,
                    o.index
                );

                emit LimitExecuted(
                    a.orderId,
                    n.index,
                    finalTrade,
                    n.nftHolder,
                    IGambitTradingStorageV1.LimitOrder.OPEN,
                    finalTrade.openPrice,
                    priceImpactP,
                    (finalTrade.initialPosToken * tokenPriceUsdc) /
                        PRECISION /
                        (10 ** (18 - usdcDecimals())),
                    0,
                    0
                );
            }
        }

        nftRewards.unregisterTrigger(
            NftRewardsInterfaceV6.TriggeredLimitId(
                n.trader,
                n.pairIndex,
                n.index,
                n.orderType
            )
        );

        storageT.unregisterPendingNftOrder(a.orderId);
    }

    function executeNftCloseOrderCallback(
        AggregatorAnswer calldata a
    ) external onlyPriceAggregator notDone {
        IGambitTradingStorageV1.PendingNftOrder memory o = storageT
            .reqID_pendingNftOrder(a.orderId);

        IGambitTradingStorageV1.Trade memory t = storageT.openTrades(
            o.trader,
            o.pairIndex,
            o.index
        );

        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();

        if (
            a.price > 0 && t.leverage > 0
            // disable checking timelock
            // && block.number >= storageT.nftLastSuccess(o.nftId) + storageT.nftSuccessTimelock()
        ) {
            IGambitTradingStorageV1.TradeInfo memory i = storageT
                .openTradesInfo(t.trader, t.pairIndex, t.index);

            IGambitPairsStorageV1 pairsStored = aggregator.pairsStorage();

            Values memory v;

            v.price = pairsStored.guaranteedSlEnabled(t.pairIndex)
                ? o.orderType == IGambitTradingStorageV1.LimitOrder.TP
                    ? t.tp
                    : o.orderType == IGambitTradingStorageV1.LimitOrder.SL
                    ? t.sl
                    : a.price
                : a.price;

            v.profitP = currentPercentProfit(
                t.openPrice,
                v.price,
                t.buy,
                t.leverage
            );
            v.levPosUsdc =
                ((t.initialPosToken * i.tokenPriceUsdc * t.leverage) / 1e18) /
                PRECISION /
                (10 ** (18 - usdcDecimals()));
            v.posUsdc = (v.levPosUsdc * 1e18) / t.leverage;

            if (o.orderType == IGambitTradingStorageV1.LimitOrder.LIQ) {
                v.liqPrice = pairInfos.getTradeLiquidationPrice(
                    t.trader,
                    t.pairIndex,
                    t.index,
                    t.openPrice,
                    t.buy,
                    v.posUsdc,
                    t.leverage
                );

                // NFT reward in USDC
                v.reward1 = (
                    t.buy ? a.price <= v.liqPrice : a.price >= v.liqPrice
                )
                    ? (v.posUsdc * 5) / 100
                    : 0;
            } else {
                // NFT reward in USDC
                v.reward1 = ((o.orderType ==
                    IGambitTradingStorageV1.LimitOrder.TP &&
                    t.tp > 0 &&
                    (t.buy ? a.price >= t.tp : a.price <= t.tp)) ||
                    (o.orderType == IGambitTradingStorageV1.LimitOrder.SL &&
                        t.sl > 0 &&
                        (t.buy ? a.price <= t.sl : a.price >= t.sl)))
                    ? (v.levPosUsdc *
                        pairsStored.pairNftLimitOrderFeeP(t.pairIndex)) /
                        100 /
                        PRECISION
                    : 0;
            }

            // If can be triggered
            if (v.reward1 > 0) {
                v.tokenPriceUsdc = aggregator.tokenPriceUsdc();

                v.usdcSentToTrader = unregisterTrade(
                    t, // trade
                    false, //marketOrder
                    v.profitP, // percentProfit
                    v.posUsdc, // currentUsdcPos
                    (i.openInterestUsdc * 1e18) / t.leverage, // initialUsdcPos
                    o.orderType == IGambitTradingStorageV1.LimitOrder.LIQ // closingFeeUsdc
                        ? v.reward1
                        : (v.levPosUsdc *
                            pairsStored.pairCloseFeeP(t.pairIndex)) /
                            100 /
                            PRECISION,
                    v.tokenPriceUsdc // tokenPriceUsdc
                );

                emit LimitExecuted(
                    a.orderId,
                    o.index,
                    t,
                    o.nftHolder,
                    o.orderType,
                    v.price,
                    0,
                    v.posUsdc,
                    v.profitP,
                    v.usdcSentToTrader
                );
            }
        }

        nftRewards.unregisterTrigger(
            NftRewardsInterfaceV6.TriggeredLimitId(
                o.trader,
                o.pairIndex,
                o.index,
                o.orderType
            )
        );

        storageT.unregisterPendingNftOrder(a.orderId);
    }

    function updateSlCallback(
        AggregatorAnswer calldata a
    ) external onlyPriceAggregator notDone {
        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();
        AggregatorInterfaceV6_2.PendingSl memory o = aggregator.pendingSlOrders(
            a.orderId
        );

        IGambitTradingStorageV1.Trade memory t = storageT.openTrades(
            o.trader,
            o.pairIndex,
            o.index
        );

        if (t.leverage > 0) {
            IGambitTradingStorageV1.TradeInfo memory i = storageT
                .openTradesInfo(o.trader, o.pairIndex, o.index);

            Values memory v;

            v.tokenPriceUsdc = aggregator.tokenPriceUsdc();
            v.levPosUsdc =
                ((t.initialPosToken * i.tokenPriceUsdc * t.leverage) / 1e18) /
                PRECISION /
                (10 ** (18 - usdcDecimals()));

            // Charge oracle fee
            v.reward1 = aggregator.pairsStorage().pairOracleFee(o.pairIndex);
            storageT.handleGovFee(v.reward1);

            t.initialPosToken -=
                (v.reward1 * (10 ** (18 - usdcDecimals())) * PRECISION) /
                i.tokenPriceUsdc;
            t.positionSizeUsdc -= v.reward1;
            storageT.updateTrade(t);

            emit OracleFeeCharged(t.trader, v.reward1);

            if (
                a.price > 0 &&
                t.buy == o.buy &&
                t.openPrice == o.openPrice &&
                (t.buy ? o.newSl <= a.price : o.newSl >= a.price)
            ) {
                storageT.updateSl(o.trader, o.pairIndex, o.index, o.newSl);

                emit SlUpdated(
                    a.orderId,
                    o.trader,
                    o.pairIndex,
                    o.index,
                    o.newSl
                );
            } else {
                emit SlCanceled(a.orderId, o.trader, o.pairIndex, o.index);
            }
        }

        aggregator.unregisterPendingSlOrder(a.orderId);
    }

    function removeCollateralCallback(
        AggregatorAnswer calldata a
    ) external onlyPriceAggregator notDone {
        IGambitTradingStorageV1.PendingRemoveCollateralOrder memory o = storageT
            .reqID_pendingRemoveCollateralOrder(a.orderId);

        IGambitTradingStorageV1.Trade memory t = storageT.openTrades(
            o.trader,
            o.pairIndex,
            o.index
        );

        if (t.leverage > 0) {
            IGambitTradingStorageV1.TradeInfo memory i = storageT
                .openTradesInfo(o.trader, o.pairIndex, o.index);

            Values memory v;
            uint amount = o.amount;

            uint newPositionSizeUsdc = t.positionSizeUsdc - amount; // underflow checked in trading contract
            uint newLeverage = (t.positionSizeUsdc * t.leverage) /
                newPositionSizeUsdc;

            // Charge oracle fee
            v.reward1 = storageT.priceAggregator().pairsStorage().pairOracleFee(
                o.pairIndex
            );
            storageT.handleGovFee(v.reward1);

            emit OracleFeeCharged(t.trader, v.reward1);

            t.initialPosToken -=
                (v.reward1 * (10 ** (18 - usdcDecimals())) * PRECISION) /
                i.tokenPriceUsdc;
            t.positionSizeUsdc -= v.reward1;
            storageT.updateTrade(t);

            v.liqPrice = pairInfos.getTradeLiquidationPrice(
                t.trader,
                t.pairIndex,
                t.index,
                t.openPrice,
                t.buy,
                (newPositionSizeUsdc * newLeverage) / 1e18,
                newLeverage
            );

            if (
                a.price > 0 &&
                t.buy == o.buy &&
                t.openPrice == o.openPrice &&
                (t.buy ? v.liqPrice <= a.price : v.liqPrice >= a.price)
            ) {
                // deduce fee from transfer amount
                amount -= v.reward1; // underflow checked in trading contract

                t.initialPosToken -=
                    (amount * (10 ** (18 - usdcDecimals())) * PRECISION) /
                    i.tokenPriceUsdc;
                t.positionSizeUsdc = newPositionSizeUsdc;
                t.leverage = newLeverage;
                storageT.updateTrade(t);

                storageT.transferUsdc(address(storageT), o.trader, amount);

                emit CollateralRemoved(
                    a.orderId,
                    o.trader,
                    o.pairIndex,
                    o.index,
                    amount,
                    newLeverage
                );
            } else {
                emit CollateralRemoveCanceled(
                    a.orderId,
                    o.trader,
                    o.pairIndex,
                    o.index
                );
            }
        }

        storageT.unregisterPendingRemoveCollateralOrder(a.orderId);
    }
}

/**
 * @dev GambitTradingCallbacksV1Facet2 with stablecoin decimals set to 6.
 */
contract GambitTradingCallbacksV1Facet2____6 is GambitTradingCallbacksV1Facet2 {
    function usdcDecimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @dev GambitTradingCallbacksV1Facet2 with stablecoin decimals set to 18.
 */
contract GambitTradingCallbacksV1Facet2____18 is
    GambitTradingCallbacksV1Facet2
{
    function usdcDecimals() public pure override returns (uint8) {
        return 18;
    }
}

