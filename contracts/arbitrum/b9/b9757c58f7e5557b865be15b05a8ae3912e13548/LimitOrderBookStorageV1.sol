// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { ILimitOrderBook } from "./ILimitOrderBook.sol";

/// @notice For future upgrades, do not change LimitOrderBookStorageV1. Create a new
/// contract which implements LimitOrderBookStorageV1 and following the naming convention
/// LimitOrderBookStorageVX.

abstract contract LimitOrderBookStorageV1 {
    address internal _clearingHouse;
    address internal _accountBalance;
    uint256 internal _minOrderValue;
    uint256 internal _feeOrderValue;
    mapping(bytes32 => ILimitOrderBook.OrderStatus) internal _ordersStatus;
    mapping(bytes32 => ILimitOrderBook.LimitOrder) internal _orders;
}

