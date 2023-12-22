// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {GmxV2Market} from "./GmxV2Market.sol";
import {GmxV2Price} from "./GmxV2Price.sol";
import {GmxV2MarketPoolValueInfo} from "./GmxV2MarketPoolValueInfo.sol";

interface IReader {
  function getMarketTokenPrice ( address dataStore, GmxV2Market memory market, GmxV2Price memory indexTokenPrice, GmxV2Price memory longTokenPrice, GmxV2Price memory shortTokenPrice, bytes32 pnlFactorType, bool maximize ) external view returns ( int256, GmxV2MarketPoolValueInfo memory );
  function getMarkets ( address dataStore, uint256 start, uint256 end ) external view returns ( GmxV2Market[] memory );
}

