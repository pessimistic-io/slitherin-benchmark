pragma solidity >= 0.8.0;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

library MathUtils {
    function diff(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a > b ? a - b : b - a;
        }
    }

    function zeroCapSub(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            return a > b ? a - b : 0;
        }
    }

    function frac(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        return FixedPointMathLib.mulDiv(x, y, denominator);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev a + (b - c) * x / y
    function addThenSubWithFraction(uint256 orig, uint256 add, uint256 sub, uint256 num, uint256 denum)
        internal
        pure
        returns (uint256)
    {
        return zeroCapSub(orig + frac(add, num, denum), frac(sub, num, denum));
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     * extract from OZ Math
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }
}

