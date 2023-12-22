// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./Keys.sol";
import "./MarketStoreUtils.sol";
import "./Position.sol";
import "./PositionUtils.sol";
import "./PositionStoreUtils.sol";
import "./OrderStoreUtils.sol";
import "./MarketUtils.sol";
import "./Market.sol";
import "./ReaderPricingUtils.sol";

// @title Reader
// @dev Library for read functions
contract ReaderLite {
    using SafeCast for uint256;
    using Position for Position.Props;

    struct GetPositionInfoCache {
        Market.Props market;
        Price.Props collateralTokenPrice;
        uint256 sizeDeltaUsd;
        int256 basePnlUsd;
    }

    function getMarketTokens(
        DataStore dataStore,
        address key
    ) public view returns (address marketToken, address indexToken, address longToken, address shortToken) {
        if (dataStore.containsAddress(Keys.MARKET_LIST, key)) {
            marketToken = dataStore.getAddress(keccak256(abi.encode(key, MarketStoreUtils.MARKET_TOKEN)));
            indexToken = dataStore.getAddress(keccak256(abi.encode(key, MarketStoreUtils.INDEX_TOKEN)));
            longToken = dataStore.getAddress(keccak256(abi.encode(key, MarketStoreUtils.LONG_TOKEN)));
            shortToken = dataStore.getAddress(keccak256(abi.encode(key, MarketStoreUtils.SHORT_TOKEN)));
        }
    }

    function isOrderExist(DataStore dataStore, bytes32 orderKey) external view returns (bool) {
        return dataStore.getAddress(keccak256(abi.encode(orderKey, OrderStoreUtils.ACCOUNT))) != address(0);
    }

    function getPositionSizeInUsd(DataStore dataStore, bytes32 positionKey) external view returns (uint256) {
        return dataStore.getUint(keccak256(abi.encode(positionKey, PositionStoreUtils.SIZE_IN_USD)));
    }

    function getPositionMarginInfo(
        DataStore dataStore,
        IReferralStorage referralStorage,
        bytes32 positionKey,
        MarketUtils.MarketPrices memory prices
    )
        external
        view
        returns (uint256 collateralAmount, uint256 sizeInUsd, uint256 totalCostAmount, int256 pnlAfterPriceImpactUsd)
    {
        GetPositionInfoCache memory cache;
        Position.Props memory position = PositionStoreUtils.get(dataStore, positionKey);
        cache.market = MarketStoreUtils.get(dataStore, position.market());
        cache.collateralTokenPrice = MarketUtils.getCachedTokenPrice(position.collateralToken(), cache.market, prices);
        cache.sizeDeltaUsd = position.sizeInUsd();
        ReaderPricingUtils.ExecutionPriceResult memory executionPriceResult = ReaderPricingUtils.getExecutionPrice(
            dataStore,
            cache.market,
            prices.indexTokenPrice,
            position.sizeInUsd(),
            position.sizeInTokens(),
            -cache.sizeDeltaUsd.toInt256(),
            position.isLong()
        );

        PositionPricingUtils.GetPositionFeesParams memory getPositionFeesParams = PositionPricingUtils
            .GetPositionFeesParams(
                dataStore, // dataStore
                referralStorage, // referralStorage
                position, // position
                cache.collateralTokenPrice, // collateralTokenPrice
                executionPriceResult.priceImpactUsd > 0, // forPositiveImpact
                cache.market.longToken, // longToken
                cache.market.shortToken, // shortToken
                cache.sizeDeltaUsd, // sizeDeltaUsd
                address(0) // uiFeeReceiver
            );

        PositionPricingUtils.PositionFees memory fees = PositionPricingUtils.getPositionFees(getPositionFeesParams);

        (cache.basePnlUsd, , ) = PositionUtils.getPositionPnlUsd(
            dataStore,
            cache.market,
            prices,
            position,
            cache.sizeDeltaUsd
        );

        collateralAmount = position.collateralAmount();
        sizeInUsd = cache.sizeDeltaUsd;
        totalCostAmount = fees.totalCostAmount;
        pnlAfterPriceImpactUsd = executionPriceResult.priceImpactUsd + cache.basePnlUsd;
    }
}

