// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.6;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

struct TokenConfig {
    /// @dev 10 ^ token decimals
    uint256 baseUnits;
    /// @dev precision of price posted by reporter
    uint256 priceUnits;
    /// @dev chainlink pricefeed used to compare with posted price
    AggregatorV3Interface chainlinkPriceFeed;
    uint256 chainlinkDeviation;
    uint256 chainlinkTimeout;
}

interface IPriceFeed {
    function postPrices(address[] calldata tokens, uint256[] calldata prices) external;
    function tokenConfig(address token) external view returns (TokenConfig memory);
}

