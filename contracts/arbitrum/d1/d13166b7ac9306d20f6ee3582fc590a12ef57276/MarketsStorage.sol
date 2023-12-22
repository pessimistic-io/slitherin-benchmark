// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { MarketType } from "./LibEnums.sol";

struct Market {
    uint256 marketId;
    string identifier;
    MarketType marketType;
    bool active;
    string baseCurrency;
    string quoteCurrency;
    string symbol;
    bytes32 muonPriceFeedId;
    bytes32 fundingRateId;
    uint256 protocolFee;
}

library MarketsStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.markets.storage");

    struct Layout {
        mapping(uint256 => Market) marketMap;
        Market[] marketList;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

