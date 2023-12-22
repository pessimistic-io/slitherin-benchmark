// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./SafeCast.sol";
import "./Math.sol";

/**
 * @title Precision
 * @dev Library for precision values and conversions
 */
library Precision {
    using SafeCast for uint256;

    uint256 public constant FLOAT_PRECISION = 10 ** 30;

    /**
     * Applies the given factor to the given value and returns the result.
     *
     * @param value The value to apply the factor to.
     * @param factor The factor to apply.
     * @return The result of applying the factor to the value.
     */
    function applyFactor(uint256 value, uint256 factor) internal pure returns (uint256) {
        return mulDiv(value, factor, FLOAT_PRECISION);
    }

    function mulDiv(uint256 value, uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return Math.mulDiv(value, numerator, denominator);
    }
}

