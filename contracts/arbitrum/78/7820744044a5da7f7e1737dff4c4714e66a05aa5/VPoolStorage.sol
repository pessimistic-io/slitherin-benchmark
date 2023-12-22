// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { DataTypes } from "./DataTypes.sol";

/// @notice For future upgrades, do not change VPoolStorageV1. Create a new
/// contract which implements VPoolStorageV1 and following the naming convention
/// VPoolStorageVX.
abstract contract VPoolStorageV1 {
    address internal __orderBook;
    address internal _accountBalance;
    address internal _clearingHouseConfig;

    address[10] private __gap1;
    uint256[10] private __gap2;

    mapping(address => int24) internal _lastUpdatedTickMap;
    mapping(address => uint256) internal _firstTradedTimestampMap;
    mapping(address => uint256) internal _lastSettledTimestampMap;
    mapping(address => uint256) internal _lastOverPriceSpreadTimestampMap;
    mapping(address => DataTypes.Growth) internal _globalFundingGrowthX96Map;

    // key: base token
    // value: a threshold to limit the price impact per block when reducing or closing the position
    mapping(address => uint24) internal _maxTickCrossedWithinBlockMap;

    // first key: trader, second key: baseToken
    // value: the last timestamp when a trader exceeds price limit when closing a position/being liquidated
    mapping(address => mapping(address => uint256)) internal _lastOverPriceLimitTimestampMap;
}

abstract contract VPoolStorageV2 is VPoolStorageV1 {
    // the last timestamp when tick is updated; for price limit check
    // key: base token
    // value: the last timestamp to update the tick
    mapping(address => uint256) internal _lastTickUpdatedTimestampMap;
}

