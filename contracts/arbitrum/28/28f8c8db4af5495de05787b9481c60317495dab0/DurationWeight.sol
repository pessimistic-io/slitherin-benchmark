// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {FeeCalculation} from "./FeeCalculation.sol";
import {Math} from "./Math.sol";

/// @title library for calculating duration weight
/// @author Timeswap Labs
library DurationWeight {
  using Math for uint256;

  /// @dev update the short returned growth given the short returned growth and the short token amount.
  /// @param liquidity The liquidity of the pool.
  /// @param shortReturnedGrowth The current amount of short returned growth.
  /// @param shortAmount The amount of short withdrawn.
  /// @param newShortReturnedGrowth The newly updated short returned growth.
  function update(
    uint160 liquidity,
    uint256 shortReturnedGrowth,
    uint256 shortAmount
  ) internal pure returns (uint256 newShortReturnedGrowth) {
    newShortReturnedGrowth = shortReturnedGrowth.unsafeAdd(FeeCalculation.getFeeGrowth(shortAmount, liquidity));
  }
}

