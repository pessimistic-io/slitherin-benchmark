// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.16;

import { AppStorage, LibAppStorage } from "./LibAppStorage.sol";

library LibMarkets {
    function isValidMarketId(uint256 marketId) internal pure returns (bool) {
        return marketId != 0;
    }
}

