//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./IERC20MetadataUpgradeable.sol";

import "./Multicall.sol";
import "./Delegatable.sol";
import "./IGambitReferralsV1.sol";
import "./IGambitPairInfosV1.sol";
import "./IGambitTradingStorageV1.sol";
import "./IGambitPairsStorageV1.sol";

import "./IStableCoinDecimals.sol";

import "./GambitErrorsV1.sol";

import "./GambitTradingV1Base.sol";

/**
 * @dev GambitTradingV1Facet3 implements updateTp, updateSl, addCollateral, removeCollateral, executeNftOrder
 */
abstract contract GambitTradingV1Facet3 is GambitTradingV1Base {
    constructor() {
        _disableInitializers();
    }

    // Manage limit order (TP/SL)
    function updateTp(
        uint pairIndex,
        uint index,
        uint newTp
    ) external notContract notDone {
        address sender = _msgSender();

        IGambitTradingStorageV1.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        IGambitTradingStorageV1.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );

        if (t.leverage == 0) revert GambitErrorsV1.NoTrade();
        if (block.number - i.tpLastUpdated < limitOrdersTimelock)
            revert GambitErrorsV1.LimitTimelock();

        storageT.updateTp(sender, pairIndex, index, newTp);

        emit TpUpdated(sender, pairIndex, index, newTp);
    }

    function updateSl(
        uint pairIndex,
        uint index,
        uint newSl
    ) external notContract notDone {
        address sender = _msgSender();

        IGambitTradingStorageV1.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        IGambitTradingStorageV1.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );

        if (t.leverage == 0) revert GambitErrorsV1.NoTrade();

        uint maxSlDist = ((t.openPrice * MAX_SL_P) * 1e18) / 100 / t.leverage;

        if (
            newSl > 0 &&
            (
                t.buy
                    ? newSl < t.openPrice - maxSlDist
                    : newSl > t.openPrice + maxSlDist
            )
        ) revert GambitErrorsV1.TooHigh();

        if (block.number - i.slLastUpdated < limitOrdersTimelock)
            revert GambitErrorsV1.LimitTimelock();

        uint oracleFee = storageT
            .priceAggregator()
            .pairsStorage()
            .pairOracleFee(t.pairIndex);
        if (t.positionSizeUsdc <= oracleFee) revert GambitErrorsV1.BelowFee();

        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();

        if (
            newSl == 0 ||
            !aggregator.pairsStorage().guaranteedSlEnabled(pairIndex)
        ) {
            storageT.updateSl(sender, pairIndex, index, newSl);

            emit SlUpdated(sender, pairIndex, index, newSl);
        } else {
            uint orderId = aggregator.getPrice(
                pairIndex,
                AggregatorInterfaceV6_2.OrderType.UPDATE_SL,
                (t.initialPosToken * i.tokenPriceUsdc * t.leverage) /
                    1e18 /
                    PRECISION /
                    (10 ** (18 - usdcDecimals()))
            );

            aggregator.storePendingSlOrder(
                orderId,
                AggregatorInterfaceV6_2.PendingSl(
                    sender,
                    pairIndex,
                    index,
                    t.openPrice,
                    t.buy,
                    newSl
                )
            );

            emit SlUpdateInitiated(
                orderId,
                sender,
                pairIndex,
                index,
                t.openPrice,
                t.buy,
                newSl
            );
        }
    }

    function addCollateral(
        uint pairIndex,
        uint index,
        uint amount
    ) external notContract notDone {
        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();
        IGambitPairsStorageV1 pairsStored = aggregator.pairsStorage();

        address sender = _msgSender();

        IGambitTradingStorageV1.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        IGambitTradingStorageV1.TradeInfo memory i = storageT.openTradesInfo(
            sender,
            pairIndex,
            index
        );

        if (t.leverage == 0) revert GambitErrorsV1.NoTrade();
        if (amount == 0) revert GambitErrorsV1.ZeroValue();

        uint newPositionSizeUsdc = t.positionSizeUsdc + amount;
        uint newLeverage = (t.positionSizeUsdc * t.leverage) /
            newPositionSizeUsdc;

        if (newPositionSizeUsdc > maxPosUsdc)
            revert GambitErrorsV1.AboveMaxPos();

        if (
            newLeverage == 0 ||
            newLeverage < pairsStored.pairMinLeverage(t.pairIndex)
        ) revert GambitErrorsV1.LeverageIncorrect();

        storageT.transferUsdc(sender, address(storageT), amount);

        // update trade
        t.initialPosToken +=
            (amount * (10 ** (18 - usdcDecimals())) * PRECISION) /
            i.tokenPriceUsdc;
        t.positionSizeUsdc = newPositionSizeUsdc;
        t.leverage = newLeverage;
        storageT.updateTrade(t);

        emit CollateralAdded(sender, pairIndex, index, amount, newLeverage);
    }

    function removeCollateral(
        uint pairIndex,
        uint index,
        uint amount
    ) external notContract notDone {
        AggregatorInterfaceV6_2 aggregator = storageT.priceAggregator();
        IGambitPairsStorageV1 pairsStored = aggregator.pairsStorage();

        address sender = _msgSender();

        if (
            storageT.pendingOrderIdsCount(sender) >=
            storageT.maxPendingMarketOrders()
        ) revert GambitErrorsV1.MaxPendingOrders();

        IGambitTradingStorageV1.Trade memory t = storageT.openTrades(
            sender,
            pairIndex,
            index
        );

        if (t.leverage == 0) revert GambitErrorsV1.NoTrade();
        if (amount == 0) revert GambitErrorsV1.ZeroValue();
        if (t.positionSizeUsdc <= amount) revert GambitErrorsV1.AbovePos();

        uint oracleFee = aggregator.pairsStorage().pairOracleFee(t.pairIndex);

        // amount should be greater than oracle fee because the fee is deducted from the withdrawal amount
        if (amount <= oracleFee) revert GambitErrorsV1.BelowFee();

        uint newPositionSizeUsdc = t.positionSizeUsdc - amount;
        uint newLeverage = (t.positionSizeUsdc * t.leverage) /
            newPositionSizeUsdc;

        // it will always pass
        // if(newPositionSizeUsdc > maxPosUsdc) revert GambitErrorsV1.AboveMaxPos();

        if (
            newLeverage == 0 ||
            newLeverage > pairsStored.pairMaxLeverage(t.pairIndex)
        ) revert GambitErrorsV1.LeverageIncorrect();

        if (
            (newPositionSizeUsdc * newLeverage) / 1e18 <
            pairsStored.pairMinLevPosUsdc(t.pairIndex)
        ) revert GambitErrorsV1.BelowMinPos();

        uint orderId = aggregator.getPrice(
            t.pairIndex,
            AggregatorInterfaceV6_2.OrderType.REMOVE_COLLATERAL,
            (t.positionSizeUsdc * t.leverage) / 1e18
        );

        storageT.storePendingRemoveCollateralOrder(
            IGambitTradingStorageV1.PendingRemoveCollateralOrder({
                trader: sender,
                pairIndex: t.pairIndex,
                index: index,
                amount: amount,
                openPrice: t.openPrice,
                buy: t.buy
            }),
            orderId
        );

        emit CollateralRemoveInitiated(
            orderId,
            sender,
            pairIndex,
            index,
            t.openPrice,
            t.buy,
            amount
        );
    }

    // Execute limit order
    function executeNftOrder(
        IGambitTradingStorageV1.LimitOrder orderType,
        address trader,
        uint pairIndex,
        uint index,
        uint nftId,
        uint nftType,
        PythStructs.Price calldata price
    ) external payable notContract notDone {
        if (nftType < 1 || nftType > 5) revert GambitErrorsV1.WrongNftType();
        if (storageT.nfts(nftType - 1).ownerOf(nftId) != _msgSender())
            revert GambitErrorsV1.NoNFT();

        // DEPRECATED: disable timelock for nft orders
        // require(
        //     block.number >=
        //         storageT.nftLastSuccess(nftId) + storageT.nftSuccessTimelock(),
        //     "SUCCESS_TIMELOCK"
        // );

        IGambitTradingStorageV1.Trade memory t;

        if (orderType == IGambitTradingStorageV1.LimitOrder.OPEN) {
            if (!storageT.hasOpenLimitOrder(trader, pairIndex, index))
                revert GambitErrorsV1.NoLimit();
        } else {
            t = storageT.openTrades(trader, pairIndex, index);

            if (t.leverage == 0) revert GambitErrorsV1.NoTrade();

            if (orderType == IGambitTradingStorageV1.LimitOrder.LIQ) {
                uint liqPrice = getTradeLiquidationPrice(t);

                if (t.sl != 0 && (t.buy ? liqPrice <= t.sl : liqPrice >= t.sl))
                    revert GambitErrorsV1.HasSl();
            } else {
                if (
                    orderType == IGambitTradingStorageV1.LimitOrder.SL &&
                    t.sl == 0
                ) revert GambitErrorsV1.NoSl();
                if (
                    orderType == IGambitTradingStorageV1.LimitOrder.TP &&
                    t.tp == 0
                ) revert GambitErrorsV1.NoTp();
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
            uint leveragedPosUsdc; // 1e6 (USDC) or 1e18 (DAI)

            if (orderType == IGambitTradingStorageV1.LimitOrder.OPEN) {
                IGambitTradingStorageV1.OpenLimitOrder memory l = storageT
                    .getOpenLimitOrder(trader, pairIndex, index);

                leveragedPosUsdc = (l.positionSize * l.leverage) / 1e18; // 1e6 (USDC) or 1e18 (DAI)

                (uint priceImpactP, ) = pairInfos.getTradePriceImpact(
                    0,
                    l.pairIndex,
                    l.buy,
                    leveragedPosUsdc
                );

                if (
                    (priceImpactP * l.leverage) / 1e18 >
                    pairInfos.maxNegativePnlOnOpenP()
                ) revert GambitErrorsV1.PriceImpactTooHigh();
            } else {
                // 1e6 (USDC) or 1e18 (DAI)
                leveragedPosUsdc =
                    // USDC: 1e18 * 1e10 / 1e10 / 1e12 = 1e6
                    // DAI:  1e18 * 1e10 / 1e10 / 1e0 = 1e18
                    (t.initialPosToken *
                        storageT
                            .openTradesInfo(trader, pairIndex, index)
                            .tokenPriceUsdc *
                        t.leverage) /
                    1e18 /
                    PRECISION /
                    (10 ** (18 - usdcDecimals()));
            }

            uint orderId = storageT.priceAggregator().getPrice(
                pairIndex,
                orderType == IGambitTradingStorageV1.LimitOrder.OPEN
                    ? AggregatorInterfaceV6_2.OrderType.LIMIT_OPEN
                    : AggregatorInterfaceV6_2.OrderType.LIMIT_CLOSE,
                leveragedPosUsdc
            );

            storageT.storePendingNftOrder(
                IGambitTradingStorageV1.PendingNftOrder({
                    nftHolder: _msgSender(),
                    nftId: nftId,
                    trader: trader,
                    pairIndex: pairIndex,
                    index: index,
                    orderType: orderType
                }),
                orderId
            );

            nftRewards.storeFirstToTrigger(triggeredLimitId, _msgSender());

            emit NftOrderInitiated(orderId, _msgSender(), trader, pairIndex);

            // fulfill on-demand price
            (uint256 price, , bool success) = storageT
                .priceAggregator()
                .fulfill{value: address(this).balance}(orderId, price); // transfer all ETH

            if (price == 0) revert GambitErrorsV1.InvalidPrice();
            if (!success) revert GambitErrorsV1.PriceFeedFailed();
        } else {
            nftRewards.storeTriggerSameBlock(triggeredLimitId, _msgSender());

            emit NftOrderSameBlock(_msgSender(), trader, pairIndex);
        }
    }
}

/**
 * @dev GambitTradingV1Facet3 with stablecoin decimals set to 6.
 */
contract GambitTradingV1Facet3____6 is GambitTradingV1Facet3 {
    function usdcDecimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @dev GambitTradingV1Facet3 with stablecoin decimals set to 6.
 */
contract GambitTradingV1Facet3____18 is GambitTradingV1Facet3 {
    function usdcDecimals() public pure override returns (uint8) {
        return 18;
    }
}

