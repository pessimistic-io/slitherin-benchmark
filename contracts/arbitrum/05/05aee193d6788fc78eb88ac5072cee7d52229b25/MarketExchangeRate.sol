// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./MarketExchangeRateLib.sol";
import "./Math.sol";

contract MarketExchangeRate {
    using Math for uint256;

    function getMarketExchangeRate(address market) external view returns (uint256){
        return Math.ONE.divDown(MarketExchangeRateLib.getMarketExchangeRate(market));
    }
}

