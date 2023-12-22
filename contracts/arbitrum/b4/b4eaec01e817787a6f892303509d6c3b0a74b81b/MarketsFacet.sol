// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { Ownable } from "./Ownable.sol";
import { LibMarkets } from "./LibMarkets.sol";
import { AppStorage, Market } from "./LibAppStorage.sol";
import "./LibEnums.sol";

contract MarketsFacet is Ownable {
    AppStorage internal s;

    event CreateMarket(uint256 indexed marketId);
    event UpdateMarketStatus(uint256 indexed marketId, bool oldStatus, bool newStatus);

    // --------------------------------//
    //----- PUBLIC WRITE FUNCTIONS ----//
    // --------------------------------//

    function createMarket(
        string memory identifier,
        MarketType marketType,
        TradingSession tradingSession,
        bool active,
        string memory baseCurrency,
        string memory quoteCurrency,
        string memory symbol
    ) external onlyOwner returns (Market memory market) {
        uint256 currentMarketId = s.markets._marketList.length + 1;
        market = Market(
            currentMarketId,
            identifier,
            marketType,
            tradingSession,
            active,
            baseCurrency,
            quoteCurrency,
            symbol
        );

        s.markets._marketMap[currentMarketId] = market;
        s.markets._marketList.push(market);

        emit CreateMarket(currentMarketId);
    }

    function updateMarketStatus(uint256 marketId, bool status) external onlyOwner {
        s.markets._marketMap[marketId].active = status;
        emit UpdateMarketStatus(marketId, !status, status);
    }

    // --------------------------------//
    //----- PUBLIC VIEW FUNCTIONS -----//
    // --------------------------------//

    function getMarketById(uint256 marketId) external view returns (Market memory market) {
        return s.markets._marketMap[marketId];
    }

    function getMarkets() external view returns (Market[] memory markets) {
        return s.markets._marketList;
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

