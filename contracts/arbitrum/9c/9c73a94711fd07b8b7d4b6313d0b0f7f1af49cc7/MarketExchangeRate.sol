// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./MarketExchangeRateLib.sol";

contract MarketExchangeRate {


    function getMarketExchangeRate(address market) external view returns (uint256){
        return MarketExchangeRateLib.getMarketExchangeRate(market);
    }
}

