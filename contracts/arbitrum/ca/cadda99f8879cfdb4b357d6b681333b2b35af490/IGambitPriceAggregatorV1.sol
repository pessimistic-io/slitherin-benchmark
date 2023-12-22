// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPyth.sol";

interface IGambitPriceAggregatorV1 {
    enum OrderType {
        MARKET_OPEN,
        MARKET_CLOSE,
        LIMIT_OPEN,
        LIMIT_CLOSE,
        REMOVE_COLLATERAL
    }

    function pyth() external returns (IPyth);

    function PYTH_PRICE_AGE() external returns (uint);

    function getPrice(uint, OrderType, uint) external returns (uint);

    function tokenPriceUsdc() external view returns (uint);

    function openFeeP(uint) external view returns (uint);
}

