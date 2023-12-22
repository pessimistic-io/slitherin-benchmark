// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, LibAppStorage, Market } from "./LibAppStorage.sol";

library LibMarkets {
    function isValidMarketId(uint256 marketId) internal pure returns (bool) {
        return marketId != 0;
    }

    function isActiveMarket(uint256 marketId) internal view returns (bool) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        return s.markets._marketMap[marketId].active;
    }
}

