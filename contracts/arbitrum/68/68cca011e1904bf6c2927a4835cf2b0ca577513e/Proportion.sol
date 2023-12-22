// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {FullMath} from "./FullMath.sol";

/// @title library for proportion utils
/// @author Timeswap Labs
library Proportion {
  /// @dev Get the balance proportion calculation.
  /// @notice Round down the result.
  /// @param multiplicand The multiplicand balance.
  /// @param multiplier The multiplier balance.
  /// @param divisor The divisor balance.
  function proportion(
    uint256 multiplicand,
    uint256 multiplier,
    uint256 divisor,
    bool roundUp
  ) internal pure returns (uint256) {
    return FullMath.mulDiv(multiplicand, multiplier, divisor, roundUp);
  }
}

