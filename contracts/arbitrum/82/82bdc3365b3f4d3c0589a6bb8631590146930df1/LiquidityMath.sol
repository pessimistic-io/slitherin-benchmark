// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IllegalArgument} from "./Errors.sol";

import {FixedPointMath} from "./FixedPointMath.sol";

/// @title  LiquidityMath
/// @author Savvy DeFi
library LiquidityMath {
    using FixedPointMath for FixedPointMath.Number;

    /// @dev Adds a signed delta to an unsigned integer.
    ///
    /// @param  x The unsigned value to add the delta to.
    /// @param  y The signed delta value to add.
    /// @return z The result.
    function addDelta(uint256 x, int256 y) internal pure returns (uint256 z) {
        if (y < 0) {
            require((z = x - uint256(-y)) < x, "IllegalArgument");
        } else {
            require((z = x + uint256(y)) >= x, "IllegalArgument");
        }
    }

    /// @dev Calculate a uint256 representation of x * y using FixedPointMath
    ///
    /// @param  x The first factor
    /// @param  y The second factor (fixed point)
    /// @return z The resulting product, after truncation
    function calculateProduct(
        uint256 x,
        FixedPointMath.Number memory y
    ) internal pure returns (uint256 z) {
        z = y.mul(x).truncate();
    }
}

