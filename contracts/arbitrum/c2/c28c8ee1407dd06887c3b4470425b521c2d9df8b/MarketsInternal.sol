// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { Decimal } from "./LibDecimal.sol";
import { ConstantsInternal } from "./ConstantsInternal.sol";
import { MarketsStorage, Market } from "./MarketsStorage.sol";
import { MasterStorage } from "./MasterStorage.sol";

library MarketsInternal {
    using MarketsStorage for MarketsStorage.Layout;
    using MasterStorage for MasterStorage.Layout;
    using Decimal for Decimal.D256;

    /* ========== VIEWS ========== */

    function getMarkets() internal view returns (Market[] memory markets) {
        return MarketsStorage.layout().marketList;
    }

    function getMarketById(uint256 marketId) internal view returns (Market memory market) {
        return MarketsStorage.layout().marketMap[marketId];
    }

    function getMarketsByIds(uint256[] memory marketIds) internal view returns (Market[] memory markets) {
        markets = new Market[](marketIds.length);
        for (uint256 i = 0; i < marketIds.length; i++) {
            markets[i] = MarketsStorage.layout().marketMap[marketIds[i]];
        }
    }

    function getMarketsInRange(uint256 start, uint256 end) internal view returns (Market[] memory markets) {
        uint256 length = end - start;
        markets = new Market[](length);

        for (uint256 i = 0; i < length; i++) {
            markets[i] = MarketsStorage.layout().marketList[start + i];
        }
    }

    function getMarketsLength() internal view returns (uint256 length) {
        return MarketsStorage.layout().marketList.length;
    }

    function getMarketFromPositionId(uint256 positionId) internal view returns (Market memory market) {
        uint256 marketId = MasterStorage.layout().allPositionsMap[positionId].marketId;
        market = MarketsStorage.layout().marketMap[marketId];
    }

    function getMarketsFromPositionIds(uint256[] calldata positionIds) internal view returns (Market[] memory markets) {
        markets = new Market[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 marketId = MasterStorage.layout().allPositionsMap[positionIds[i]].marketId;
            markets[i] = MarketsStorage.layout().marketMap[marketId];
        }
    }

    function getMarketProtocolFee(uint256 marketId) internal view returns (Decimal.D256 memory) {
        uint256 fee = MarketsStorage.layout().marketMap[marketId].protocolFee;
        return Decimal.ratio(fee, ConstantsInternal.getPercentBase());
    }

    function isValidMarketId(uint256 marketId) internal pure returns (bool) {
        return marketId > 0;
    }

    function isActiveMarket(uint256 marketId) internal view returns (bool) {
        return MarketsStorage.layout().marketMap[marketId].active;
    }
}

