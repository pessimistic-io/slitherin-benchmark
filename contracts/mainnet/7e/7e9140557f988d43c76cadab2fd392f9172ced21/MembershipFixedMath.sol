// SPDX-License-Identifier: MIT
// solhint-disable var-name-mixedcase

pragma solidity ^0.8.16;

import {SafeCastUpgradeable as SafeCast} from "./SafeCastUpgradeable.sol";

import {FixedMath0x} from "./FixedMath0x.sol";

using SafeCast for uint256;

library MembershipFixedMath {
  error InvalidFraction(uint256 n, uint256 d);

  /**
   * @notice Convert some uint256 fraction `n` numerator / `d` denominator to a fixed-point number `f`.
   * @param n numerator
   * @param d denominator
   * @return fixed-point number
   */
  function toFixed(uint256 n, uint256 d) internal pure returns (int256) {
    if (d.toInt256() < n.toInt256()) revert InvalidFraction(n, d);

    return (n.toInt256() * FixedMath0x.FIXED_1) / int256(d.toInt256());
  }

  /**
   * @notice Divide some unsigned int `u` by a fixed point number `f`
   * @param u unsigned dividend
   * @param f fixed point divisor, in FIXED_1 units
   * @return unsigned int quotient
   */
  function uintDiv(uint256 u, int256 f) internal pure returns (uint256) {
    // multiply `u` by FIXED_1 to cancel out the built-in FIXED_1 in f
    return uint256((u.toInt256() * FixedMath0x.FIXED_1) / f);
  }

  /**
   * @notice Multiply some unsigned int `u` by a fixed point number `f`
   * @param u unsigned multiplicand
   * @param f fixed point multiplier, in FIXED_1 units
   * @return unsigned int product
   */
  function uintMul(uint256 u, int256 f) internal pure returns (uint256) {
    // divide the product by FIXED_1 to cancel out the built-in FIXED_1 in f
    return uint256((u.toInt256() * f) / FixedMath0x.FIXED_1);
  }

  /// @notice see FixedMath0x
  function ln(int256 x) internal pure returns (int256 r) {
    return FixedMath0x.ln(x);
  }

  /// @notice see FixedMath0x
  function exp(int256 x) internal pure returns (int256 r) {
    return FixedMath0x.exp(x);
  }
}

