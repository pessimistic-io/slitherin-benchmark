// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "./IAmm.sol";
import "./Decimal.sol";

library Structs {
    enum OrderType {
        SELL_LO, 
        BUY_LO, 
        SELL_SLO,
        BUY_SLO
    }

    struct Position {
        IAmm amm;
        Decimal.decimal quoteAssetAmount;
        Decimal.decimal slippage;
        Decimal.decimal leverage;
    }

    struct Order {
        // ordertype, account, expirationTimestamp
        uint256 detail;
        uint256 trigger;
        Position position;
    }
}
