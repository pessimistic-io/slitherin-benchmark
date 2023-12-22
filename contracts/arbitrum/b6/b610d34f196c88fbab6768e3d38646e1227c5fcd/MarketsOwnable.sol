// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { AccessControlInternal } from "./AccessControlInternal.sol";
import { MarketsStorage, Market } from "./MarketsStorage.sol";
import { MarketType } from "./LibEnums.sol";
import { IMarketsEvents } from "./IMarketsEvents.sol";

contract MarketsOwnable is AccessControlInternal, IMarketsEvents {
    using MarketsStorage for MarketsStorage.Layout;

    function createMarket(
        string calldata identifier,
        MarketType marketType,
        bool active,
        string calldata baseCurrency,
        string calldata quoteCurrency,
        string calldata symbol,
        bytes32 muonPriceFeedId,
        bytes32 fundingRateId,
        uint256 protocolFee
    ) external onlyRole(ADMIN_ROLE) returns (Market memory market) {
        MarketsStorage.Layout storage s = MarketsStorage.layout();

        uint256 currentMarketId = s.marketList.length + 1;
        market = Market(
            currentMarketId,
            identifier,
            marketType,
            active,
            baseCurrency,
            quoteCurrency,
            symbol,
            muonPriceFeedId,
            fundingRateId,
            protocolFee
        );

        s.marketMap[currentMarketId] = market;
        s.marketList.push(market);

        emit CreateMarket(currentMarketId, block.timestamp);
    }

    function updateMarketIdentifier(uint256 marketId, string calldata identifier) external onlyRole(ADMIN_ROLE) {
        MarketsStorage.Layout storage s = MarketsStorage.layout();

        string memory oldIdentifier = s.marketMap[marketId].identifier;
        s.marketMap[marketId].identifier = identifier;

        emit UpdateMarketIdentifier(marketId, oldIdentifier, identifier);
    }

    function updateMarketActive(uint256 marketId, bool active) external onlyRole(ADMIN_ROLE) {
        MarketsStorage.Layout storage s = MarketsStorage.layout();

        bool oldStatus = s.marketMap[marketId].active;
        s.marketMap[marketId].active = active;

        emit UpdateMarketActive(marketId, oldStatus, active);
    }

    function updateMarketSymbol(uint256 marketId, string calldata symbol) external onlyRole(ADMIN_ROLE) {
        MarketsStorage.Layout storage s = MarketsStorage.layout();

        string memory oldSymbol = s.marketMap[marketId].symbol;
        s.marketMap[marketId].symbol = symbol;

        emit UpdateMarketSymbol(marketId, oldSymbol, symbol);
    }

    function updateMarketMuonPriceFeedId(uint256 marketId, bytes32 muonPriceFeedId) external onlyRole(ADMIN_ROLE) {
        MarketsStorage.Layout storage s = MarketsStorage.layout();

        bytes32 oldMuonPriceFeedId = s.marketMap[marketId].muonPriceFeedId;
        s.marketMap[marketId].muonPriceFeedId = muonPriceFeedId;

        emit UpdateMarketMuonPriceFeedId(marketId, oldMuonPriceFeedId, muonPriceFeedId);
    }

    function updateMarketFundingRateId(uint256 marketId, bytes32 fundingRateId) external onlyRole(ADMIN_ROLE) {
        MarketsStorage.Layout storage s = MarketsStorage.layout();

        bytes32 oldFundingRateId = s.marketMap[marketId].fundingRateId;
        s.marketMap[marketId].fundingRateId = fundingRateId;

        emit UpdateMarketFundingRateId(marketId, oldFundingRateId, fundingRateId);
    }

    function updateMarketProtocolFee(uint256 marketId, uint256 protocolFee) external onlyRole(ADMIN_ROLE) {
        MarketsStorage.Layout storage s = MarketsStorage.layout();

        uint256 oldProtocolFee = s.marketMap[marketId].protocolFee;
        s.marketMap[marketId].protocolFee = protocolFee;

        emit UpdateProtocolFee(marketId, oldProtocolFee, protocolFee);
    }
}

