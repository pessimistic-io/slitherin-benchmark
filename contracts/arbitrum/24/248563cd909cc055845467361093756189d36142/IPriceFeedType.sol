// SPDX-License-Identifier: BUSL-1.1

// (c) Gearbox Holdings, 2022

// This code was largely inspired by Gearbox Protocol

pragma solidity 0.8.16;

// NOTE: new values must always be added at the end of the enum

enum PriceFeedType {
  COMPOSITE_ORACLE
}

interface IPriceFeedType {
  /// @dev Returns the price feed type
  function priceFeedType() external view returns (PriceFeedType);

  /// @dev Returns whether sanity checks on price feed result should be skipped
  function skipPriceCheck() external view returns (bool);
}

