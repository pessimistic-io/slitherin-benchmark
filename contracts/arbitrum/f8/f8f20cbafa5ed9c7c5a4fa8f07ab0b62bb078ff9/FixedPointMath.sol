// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/**
 * @notice A library which implements fixed point decimal math.
 */
library FixedPointMath {
    /** @dev This will give approximately 60 bits of precision */
    uint256 public constant DECIMALS = 18;
    uint256 public constant ONE = 10 ** DECIMALS;

    /**
     * @notice A struct representing a fixed point decimal.
     */
    struct Number {
        uint256 n;
    }

    /**
     * @notice Encodes a unsigned 256-bit integer into a fixed point decimal.
     *
     * @param value The value to encode.
     * @return      The fixed point decimal representation.
     */
    function encode(uint256 value) internal pure returns (Number memory) {
        return Number(FixedPointMath.encodeRaw(value));
    }

    /**
     * @notice Encodes a unsigned 256-bit integer into a uint256 representation of a
     *         fixed point decimal.
     *
     * @param value The value to encode.
     * @return      The fixed point decimal representation.
     */
    function encodeRaw(uint256 value) internal pure returns (uint256) {
        return value * ONE;
    }

    /**
     * @notice Creates a rational fraction as a Number from two uint256 values
     *
     * @param n The numerator.
     * @param d The denominator.
     * @return  The fixed point decimal representation.
     */
    function rational(
        uint256 n,
        uint256 d
    ) internal pure returns (Number memory) {
        Number memory numerator = encode(n);
        return FixedPointMath.div(numerator, d);
    }

    /**
     * @notice Adds two fixed point decimal numbers together.
     *
     * @param self  The left hand operand.
     * @param value The right hand operand.
     * @return      The result.
     */
    function add(
        Number memory self,
        Number memory value
    ) internal pure returns (Number memory) {
        return Number(self.n + value.n);
    }

    /**
     * @notice Subtract a fixed point decimal from another.
     *
     * @param self  The left hand operand.
     * @param value The right hand operand.
     * @return      The result.
     */
    function sub(
        Number memory self,
        Number memory value
    ) internal pure returns (Number memory) {
        return Number(self.n - value.n);
    }

    /**
     * @notice Multiplies a fixed point decimal by an unsigned 256-bit integer.
     *
     * @param self  The fixed point decimal to multiply.
     * @param value The unsigned 256-bit integer to multiply by.
     * @return      The result.
     */
    function mul(
        Number memory self,
        uint256 value
    ) internal pure returns (Number memory) {
        return Number(self.n * value);
    }

    /**
     * @notice Divides a fixed point decimal by an unsigned 256-bit integer.
     *
     * @param self  The fixed point decimal to multiply by.
     * @param value The unsigned 256-bit integer to divide by.
     * @return      The result.
     */
    function div(
        Number memory self,
        uint256 value
    ) internal pure returns (Number memory) {
        return Number(self.n / value);
    }

    /**
     * @notice Truncates a fixed point decimal into an unsigned 256-bit integer.
     *
     * @return The integer portion of the fixed point decimal.
     */
    function truncate(Number memory self) internal pure returns (uint256) {
        return self.n / ONE;
    }
}

