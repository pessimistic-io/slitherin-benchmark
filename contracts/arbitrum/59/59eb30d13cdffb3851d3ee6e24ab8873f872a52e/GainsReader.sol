// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./GNSPairInfosV6_1.sol";
import "./GNSTradingV6_4_1.sol";
import "./GNSTradingStorageV5.sol";
import "./GNSTradingCallbacksV6_3_2.sol";

contract GainsReader {
    struct PairOpenInterestDai {
        uint256 long;
        uint256 short;
        uint256 max;
    }

    struct PairInfo {
        uint256 onePercentDepthAbove; // DAI
        uint256 onePercentDepthBelow; // DAI
        uint256 rolloverFeePerBlockP; // PRECISION (%)
        uint256 fundingFeePerBlockP; // PRECISION (%)
        uint256 accPerCollateral; // 1e18 (DAI)
        uint256 lastRolloverUpdateBlock;
        int256 accPerOiLong; // 1e18 (DAI)
        int256 accPerOiShort; // 1e18 (DAI)
        uint256 lastFundingUpdateBlock;
    }

    struct GainsConfig {
        GNSPairsStorageV6.Fee[] fees;
        GNSPairsStorageV6.Group[] groups;
        GNSTradingV6_4_1 trading;
        address callbacks;
        uint256 maxTradesPerPair;
        address[] supportedTokens;
        address oracleRewards;
        uint256 maxPosDai;
        bool isPaused;
        uint256 maxNegativePnlOnOpenP;
        uint256 pairsCount;
    }

    struct PairLeverage {
        uint pairMinLeverage;
        uint pairMaxLeverage;
    }

    struct GainsPair {
        GNSPairsStorageV6.Pair pair;
        PairOpenInterestDai openInterestDai;
        PairInfo pairInfo;
        PairLeverage pairLeverage; 
    }

    struct PositionInfo {
        GNSTradingStorageV5.Trade trade;
        GNSTradingStorageV5.TradeInfo tradeInfo;
        int256 initialFundingFeePerOi;
        uint256 initialRolloverFeePerCollateral;
        uint256 pendingAccRolloverFee;
        int256 pendingAccFundingFeeValueLong;
        int256 pendingAccFundingFeeValueShort;
    }

    struct MarketOrder {
        uint256 id;
        GNSTradingStorageV5.PendingMarketOrder order;
    }

    GNSPairsStorageV6 public immutable pairStorage;
    GNSTradingStorageV5 public immutable tradingStorage;

    // 0xf67df2a4339ec1591615d94599081dd037960d4b
    // 0xcfa6ebd475d89db04cad5a756fff1cb2bc5be33c
    constructor(GNSPairsStorageV6 pairStorage_, GNSTradingStorageV5 tradingStorage_) {
        pairStorage = pairStorage_;
        tradingStorage = tradingStorage_;
    }

    function getPairsCount() external view returns (uint256) {
        return pairStorage.pairsCount();
    }

    function config() external view returns (GainsConfig memory) {
        GNSTradingV6_4_1 trading = GNSTradingV6_4_1(tradingStorage.trading());
        GNSPairInfosV6_1 pairInfo = trading.pairInfos();
        uint256 feesCount = pairStorage.feesCount();
        uint256 groupsCount = pairStorage.groupsCount();

        GainsConfig memory gainsInfo = GainsConfig(
            new GNSPairsStorageV6.Fee[](feesCount),
            new GNSPairsStorageV6.Group[](groupsCount),
            trading,
            tradingStorage.callbacks(),
            tradingStorage.maxTradesPerPair(),
            tradingStorage.getSupportedTokens(),
            address(trading.oracleRewards()),
            trading.maxPosDai(),
            trading.isPaused(),
            pairInfo.maxNegativePnlOnOpenP(),
            pairStorage.pairsCount()
        );

        for (uint256 i = 0; i < feesCount; i++) {
            GNSPairsStorageV6.Fee memory fee = gainsInfo.fees[i];
            (
                fee.name,
                fee.openFeeP,
                fee.closeFeeP,
                fee.oracleFeeP,
                fee.nftLimitOrderFeeP,
                fee.referralFeeP,
                fee.minLevPosDai
            ) = pairStorage.fees(i);
        }
        for (uint256 i = 0; i < groupsCount; i++) {
            GNSPairsStorageV6.Group memory group = gainsInfo.groups[i];
            (group.name, group.job, group.minLeverage, group.maxLeverage, group.maxCollateralP) = pairStorage.groups(i);
        }

        return gainsInfo;
    }

    function pair(uint256 pairIndex) external view returns (GainsPair memory gainsPair) {
        GNSTradingV6_4_1 trading = GNSTradingV6_4_1(tradingStorage.trading());
        GNSTradingCallbacksV6_3_2 tradingCallbacks = GNSTradingCallbacksV6_3_2(tradingStorage.callbacks());

        GNSPairInfosV6_1 pairInfo = trading.pairInfos();

        GNSPairsStorageV6.Pair memory p = gainsPair.pair;

        (p.from, p.to, p.feed, p.spreadP, p.groupIndex, p.feeIndex) = pairStorage.pairs(pairIndex);
        gainsPair.openInterestDai = PairOpenInterestDai(
            tradingStorage.openInterestDai(pairIndex, 0),
            tradingStorage.openInterestDai(pairIndex, 1),
            tradingStorage.openInterestDai(pairIndex, 2)
        );
        PairInfo memory pairInfoItem = gainsPair.pairInfo;
        (
            pairInfoItem.onePercentDepthAbove,
            pairInfoItem.onePercentDepthBelow,
            pairInfoItem.rolloverFeePerBlockP,
            pairInfoItem.fundingFeePerBlockP
        ) = pairInfo.pairParams(pairIndex);
        (pairInfoItem.accPerCollateral, pairInfoItem.lastRolloverUpdateBlock) = pairInfo.pairRolloverFees(pairIndex);
        (pairInfoItem.accPerOiLong, pairInfoItem.accPerOiShort, pairInfoItem.lastFundingUpdateBlock) = pairInfo
            .pairFundingFees(pairIndex);

        // copied from GNSTradingV6_3_2.sol
        uint callbacksMaxLev = tradingCallbacks.pairMaxLeverage(pairIndex);
        uint pairMaxLeverage = callbacksMaxLev > 0 ? callbacksMaxLev : pairStorage.pairMaxLeverage(pairIndex);  

        gainsPair.pairLeverage = PairLeverage(
            pairStorage.pairMinLeverage(pairIndex),
            pairMaxLeverage
        );

    }

    function getLimitOrders(address trader)
        external
        view
        returns (
            GNSTradingStorageV5.OpenLimitOrder[] memory openLimitOrders,
            IGNSOracleRewardsV6_4_1.OpenLimitOrderType[] memory openLimitOrderTypes
        )
    {
        GNSTradingV6_4_1 trading = GNSTradingV6_4_1(tradingStorage.trading());
        IGNSOracleRewardsV6_4_1 oracleRewards = trading.oracleRewards();
        uint256 maxTradesPerPair = tradingStorage.maxTradesPerPair();
        uint256 pairsCount = pairStorage.pairsCount();

        uint256[] memory limitOrderCounts = new uint256[](pairsCount);
        uint256 total;
        for (uint256 pairIndex = 0; pairIndex < pairsCount; pairIndex++) {
            limitOrderCounts[pairIndex] = tradingStorage.openLimitOrdersCount(trader, pairIndex);
            total += limitOrderCounts[pairIndex];
        }

        openLimitOrders = new GNSTradingStorageV5.OpenLimitOrder[](total);
        openLimitOrderTypes = new IGNSOracleRewardsV6_4_1.OpenLimitOrderType[](total);
        uint256 openLimitOrderIndex;
        if (total > 0) {
            for (uint256 pairIndex = 0; pairIndex < pairsCount; pairIndex++) {
                if (limitOrderCounts[pairIndex] > 0) {
                    // orders could be [order, empty, order] and limitOrderCounts will be 2
                    for (uint256 orderIndex = 0; orderIndex < maxTradesPerPair; orderIndex++) {
                        if (tradingStorage.hasOpenLimitOrder(trader, pairIndex, orderIndex)) {
                            openLimitOrders[openLimitOrderIndex] = tradingStorage.getOpenLimitOrder(
                                trader,
                                pairIndex,
                                orderIndex
                            );
                            openLimitOrderTypes[openLimitOrderIndex] = oracleRewards.openLimitOrderTypes(
                                trader,
                                pairIndex,
                                orderIndex
                            );
                            openLimitOrderIndex++;
                        }
                    }
                }
            }
        }
    }

    function getPositionsAndMarketOrders(address trader)
        external
        view
        returns (PositionInfo[] memory positionInfos, MarketOrder[] memory marketOrders)
    {
        GNSPairInfosV6_1 pairInfo;
        {
            GNSTradingV6_4_1 trading = GNSTradingV6_4_1(tradingStorage.trading());
            pairInfo = trading.pairInfos();
        }
        uint256 pairsCount = pairStorage.pairsCount();

        uint256[] memory openTradesCount = new uint256[](pairsCount);
        uint256 total;
        for (uint256 pairIndex = 0; pairIndex < pairsCount; pairIndex++) {
            openTradesCount[pairIndex] = tradingStorage.openTradesCount(trader, pairIndex);
            total += openTradesCount[pairIndex];
        }

        positionInfos = new PositionInfo[](total);
        uint256 positionInfoIndex;
        if (total > 0) {
            uint256 maxTradesPerPair = tradingStorage.maxTradesPerPair();
            for (uint256 pairIndex = 0; pairIndex < pairsCount; pairIndex++) {
                if (openTradesCount[pairIndex] > 0) {
                    positionInfoIndex = _getPositionInfo(
                        positionInfos,
                        positionInfoIndex,
                        pairInfo,
                        trader,
                        pairIndex,
                        maxTradesPerPair
                    );
                }
            }
        }

        uint256[] memory pendingOrderIds = tradingStorage.getPendingOrderIds(trader);
        marketOrders = new MarketOrder[](pendingOrderIds.length);
        for (uint256 i = 0; i < pendingOrderIds.length; i++) {
            marketOrders[i].id = pendingOrderIds[i];
            GNSTradingStorageV5.PendingMarketOrder memory order = marketOrders[i].order;
            (
                order.trade,
                order.block,
                order.wantedPrice,
                order.slippageP,
                order.spreadReductionP,
                order.tokenId
            ) = tradingStorage.reqID_pendingMarketOrder(pendingOrderIds[i]);
        }
    }

    function _getPositionInfo(
        PositionInfo[] memory positionInfos,
        uint256 positionInfoIndex,
        GNSPairInfosV6_1 pairInfo,
        address trader,
        uint256 pairIndex,
        uint256 maxTradesPerPair
    ) internal view returns (uint256 newPositionInfoIndex) {
        newPositionInfoIndex = positionInfoIndex;
        uint256 pendingAccRolloverFee = pairInfo.getPendingAccRolloverFees(pairIndex);
        (int256 pendingAccFundingFeeLong, int256 pendingAccFundingFeeShort) = pairInfo.getPendingAccFundingFees(
            pairIndex
        );
        // positions could be [position, empty, position] and openTradesCount will be 2
        for (uint256 orderIndex = 0; orderIndex < maxTradesPerPair; orderIndex++) {
            GNSTradingStorageV5.Trade memory trade = getOpenTrades(trader, pairIndex, orderIndex);
            if (trade.trader == trader && trade.pairIndex == pairIndex && trade.index == orderIndex) {
                GNSTradingStorageV5.TradeInfo memory tradeInfo;
                (
                    tradeInfo.tokenId,
                    tradeInfo.tokenPriceDai, // PRECISION
                    tradeInfo.openInterestDai, // 1e18
                    tradeInfo.tpLastUpdated,
                    tradeInfo.slLastUpdated,
                    tradeInfo.beingMarketClosed
                ) = tradingStorage.openTradesInfo(trader, pairIndex, orderIndex);
                positionInfos[newPositionInfoIndex] = PositionInfo(
                    trade,
                    tradeInfo,
                    pairInfo.getTradeInitialAccFundingFeesPerOi(trader, pairIndex, orderIndex),
                    pairInfo.getTradeInitialAccRolloverFeesPerCollateral(trader, pairIndex, orderIndex),
                    pendingAccRolloverFee,
                    pendingAccFundingFeeLong,
                    pendingAccFundingFeeShort
                );
                newPositionInfoIndex++;
            }
        }
    }

    function getOpenTrades(
        address trader,
        uint256 pairIndex,
        uint256 orderIndex
    ) internal view returns (GNSTradingStorageV5.Trade memory trade) {
        (bool success, bytes memory data) = address(tradingStorage).staticcall(
            abi.encodeWithSignature("openTrades(address,uint256,uint256)", trader, pairIndex, orderIndex)
        );
        require(success, "openTrades revert");
        require(data.length >= 32 * 10, "openTrades broken");
        assembly {
            mstore(add(trade, 0), mload(add(data, 32)))
            mstore(add(trade, 32), mload(add(data, 64)))
            mstore(add(trade, 64), mload(add(data, 96)))
            mstore(add(trade, 96), mload(add(data, 128)))
            mstore(add(trade, 128), mload(add(data, 160)))
            mstore(add(trade, 160), mload(add(data, 192)))
            mstore(add(trade, 192), mload(add(data, 224)))
            mstore(add(trade, 224), mload(add(data, 256)))
            mstore(add(trade, 256), mload(add(data, 288)))
            mstore(add(trade, 288), mload(add(data, 320)))
        }
    }
}

