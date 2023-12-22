// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, LibAppStorage } from "./LibAppStorage.sol";

library LibMarkets {
    function isValidMarketId(uint256 marketId) internal view returns (bool) {
        AppStorage storage s = LibAppStorage.diamondStorage();
        uint256 length = s.markets._marketList.length;
        return marketId < length;
    }
}

