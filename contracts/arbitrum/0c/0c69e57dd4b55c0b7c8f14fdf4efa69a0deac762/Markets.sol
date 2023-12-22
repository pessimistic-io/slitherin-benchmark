// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { MarketsInternal } from "./MarketsInternal.sol";
import { Market } from "./MarketsStorage.sol";

contract Markets {
    function getMarkets() external view returns (Market[] memory markets) {
        return MarketsInternal.getMarkets();
    }

    function getMarketById(uint256 marketId) external view returns (Market memory market) {
        return MarketsInternal.getMarketById(marketId);
    }

    function getMarketsByIds(uint256[] memory marketIds) external view returns (Market[] memory markets) {
        return MarketsInternal.getMarketsByIds(marketIds);
    }

    function getMarketsInRange(uint256 start, uint256 end) external view returns (Market[] memory markets) {
        return MarketsInternal.getMarketsInRange(start, end);
    }

    function getMarketsLength() external view returns (uint256 length) {
        return MarketsInternal.getMarketsLength();
    }

    function getMarketFromPositionId(uint256 positionId) external view returns (Market memory market) {
        return MarketsInternal.getMarketFromPositionId(positionId);
    }

    function getMarketsFromPositionIds(uint256[] calldata positionIds) external view returns (Market[] memory markets) {
        return MarketsInternal.getMarketsFromPositionIds(positionIds);
    }

    function getMarketProtocolFee(uint256 marketId) external view returns (uint256) {
        return MarketsInternal.getMarketProtocolFee(marketId).value;
    }

    function isValidMarketId(uint256 marketId) external pure returns (bool) {
        return MarketsInternal.isValidMarketId(marketId);
    }

    function isActiveMarket(uint256 marketId) external view returns (bool) {
        return MarketsInternal.isActiveMarket(marketId);
    }
}

