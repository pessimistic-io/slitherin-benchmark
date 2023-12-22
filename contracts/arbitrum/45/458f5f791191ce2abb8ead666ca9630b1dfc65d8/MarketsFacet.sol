// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { Ownable } from "./Ownable.sol";
import { LibMarkets } from "./LibMarkets.sol";
import { AppStorage, Market } from "./LibAppStorage.sol";
import "./LibEnums.sol";

contract MarketsFacet is Ownable {
    AppStorage internal s;

    event CreateMarket(uint256 indexed marketId);
    event UpdateMarketIdentifier(uint256 indexed marketId, string oldIdentifier, string newIdentifier);
    event UpdateMarketActive(uint256 indexed marketId, bool oldStatus, bool newStatus);
    event UpdateMarketMuonPriceFeedId(uint256 indexed marketId, bytes32 oldMuonPriceFeedId, bytes32 newMuonPriceFeedId);
    event UpdateMarketFundingRateId(uint256 indexed marketId, bytes32 oldFundingRateId, bytes32 newFundingRateId);

    /*------------------------*
     * PUBLIC WRITE FUNCTIONS *
     *------------------------*/

    function createMarket(
        string calldata identifier,
        MarketType marketType,
        bool active,
        string calldata baseCurrency,
        string calldata quoteCurrency,
        string calldata symbol,
        bytes32 muonPriceFeedId,
        bytes32 fundingRateId
    ) external onlyOwner returns (Market memory market) {
        uint256 currentMarketId = s.markets._marketList.length + 1;
        market = Market(
            currentMarketId,
            identifier,
            marketType,
            active,
            baseCurrency,
            quoteCurrency,
            symbol,
            muonPriceFeedId,
            fundingRateId
        );

        s.markets._marketMap[currentMarketId] = market;
        s.markets._marketList.push(market);

        emit CreateMarket(currentMarketId);
    }

    function updateMarketIdentifier(uint256 marketId, string calldata identifier) external onlyOwner {
        string memory oldIdentifier = s.markets._marketMap[marketId].identifier;
        s.markets._marketMap[marketId].identifier = identifier;
        emit UpdateMarketIdentifier(marketId, oldIdentifier, identifier);
    }

    function updateMarketActive(uint256 marketId, bool active) external onlyOwner {
        bool oldStatus = s.markets._marketMap[marketId].active;
        s.markets._marketMap[marketId].active = active;
        emit UpdateMarketActive(marketId, oldStatus, active);
    }

    function updateMarketMuonPriceFeedId(uint256 marketId, bytes32 muonPriceFeedId) external onlyOwner {
        bytes32 oldMuonPriceFeedId = s.markets._marketMap[marketId].muonPriceFeedId;
        s.markets._marketMap[marketId].muonPriceFeedId = muonPriceFeedId;
        emit UpdateMarketMuonPriceFeedId(marketId, oldMuonPriceFeedId, muonPriceFeedId);
    }

    function updateMarketFundingRateId(uint256 marketId, bytes32 fundingRateId) external onlyOwner {
        bytes32 oldFundingRateId = s.markets._marketMap[marketId].fundingRateId;
        s.markets._marketMap[marketId].fundingRateId = fundingRateId;
        emit UpdateMarketFundingRateId(marketId, oldFundingRateId, fundingRateId);
    }

    /*-----------------------*
     * PUBLIC VIEW FUNCTIONS *
     *-----------------------*/

    function getMarkets() external view returns (Market[] memory markets) {
        return s.markets._marketList;
    }

    function getMarketById(uint256 marketId) external view returns (Market memory market) {
        return s.markets._marketMap[marketId];
    }

    function getMarketsByIds(uint256[] memory marketIds) external view returns (Market[] memory markets) {
        markets = new Market[](marketIds.length);
        for (uint256 i = 0; i < marketIds.length; i++) {
            markets[i] = s.markets._marketMap[marketIds[i]];
        }
    }

    function getMarketsInRange(uint256 start, uint256 end) external view returns (Market[] memory markets) {
        uint256 length = end - start;
        markets = new Market[](length);

        for (uint256 i = 0; i < length; i++) {
            markets[i] = s.markets._marketList[start + i];
        }
    }

    function getMarketsLength() external view returns (uint256 length) {
        return s.markets._marketList.length;
    }

    function getMarketFromPositionId(uint256 positionId) external view returns (Market memory market) {
        uint256 marketId = s.ma._allPositionsMap[positionId].marketId;
        market = s.markets._marketMap[marketId];
    }

    function getMarketsFromPositionIds(uint256[] calldata positionIds) external view returns (Market[] memory markets) {
        markets = new Market[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 marketId = s.ma._allPositionsMap[positionIds[i]].marketId;
            markets[i] = s.markets._marketMap[marketId];
        }
    }
}

