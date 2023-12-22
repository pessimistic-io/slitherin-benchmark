// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {FeeCalculation} from "./FeeCalculation.sol";
import {Math} from "./Math.sol";

/// @title library for calculating duration weight
/// @author Timeswap Labs
library DurationWeight {
  using Math for uint256;

  /// @dev update the short fee growth given the short fee growth and the short token amount.
  /// @param liquidity The liquidity of the pool.
  /// @param shortFeeGrowth The current amount of short fee growth.
  /// @param shortAmount The amount of short withdrawn.
  /// @param newShortFeeGrowth The newly updated short fee growth.
  function update(
    uint160 liquidity,
    uint256 shortFeeGrowth,
    uint256 shortAmount
  ) internal pure returns (uint256 newShortFeeGrowth) {
    newShortFeeGrowth = shortFeeGrowth.unsafeAdd(FeeCalculation.getFeeGrowth(shortAmount, liquidity));
  }
}

