// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @notice Exp is a struct which stores decimals with a fixed precision of 18 decimal places.
 *         Thus, if we wanted to store the 5.1, mantissa would store 5.1e18. That is:
 *         `Exp({mantissa: 5100000000000000000})`.
 */
contract ExponentialNoError {
    uint256 constant expScale = 1e18;
    uint256 constant doubleScale = 1e36;
    uint256 constant halfExpScale = expScale / 2;
    uint256 constant mantissaOne = expScale;

    struct Exp {
        uint256 mantissa;
    }

    struct Double {
        uint256 mantissa;
    }

    /**
     * @dev Truncates the given exp to a whole number value.
     *      For example, truncate(Exp{mantissa: 15 * expScale}) = 15
     */
    function truncate(Exp memory _exp) internal pure returns (uint256) {
        // Note: We are not using careful math here as we're performing a division that cannot fail
        return _exp.mantissa / expScale;
    }

    /**
     * @dev Multiply an Exp by a scalar, then truncate to return an unsigned integer.
     */
    function mul_ScalarTruncate(
        Exp memory _a,
        uint256 _scalar
    ) internal pure returns (uint256) {
        Exp memory product = mul_(_a, _scalar);
        return truncate(product);
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then add an to an unsigned integer, returning an unsigned integer.
     */
    function mul_ScalarTruncateAddUInt(
        Exp memory _a,
        uint256 _scalar,
        uint256 _addend
    ) internal pure returns (uint256) {
        Exp memory product = mul_(_a, _scalar);
        return add_(truncate(product), _addend);
    }

    /**
     * @dev Multiply an Exp by a scalar, truncate, then minus an unsigned integer, returning an unsigned integer.
     */
    function mul_ScalarTruncateSubUInt(
        Exp memory _a,
        uint256 _scalar,
        uint256 _minus
    ) internal pure returns (uint256) {
        Exp memory product = mul_(_a, _scalar);
        return sub_(truncate(product), _minus);
    }

    /**
     * @dev Checks if first Exp is less than second Exp.
     */
    function lessThanExp(
        Exp memory _left,
        Exp memory _right
    ) internal pure returns (bool) {
        return _left.mantissa < _right.mantissa;
    }

    /**
     * @dev Checks if left Exp <= right Exp.
     */
    function lessThanOrEqualExp(
        Exp memory _left,
        Exp memory _right
    ) internal pure returns (bool) {
        return _left.mantissa <= _right.mantissa;
    }

    /**
     * @dev Checks if left Exp > right Exp.
     */
    function greaterThanExp(
        Exp memory _left,
        Exp memory _right
    ) internal pure returns (bool) {
        return _left.mantissa > _right.mantissa;
    }

    /**
     * @dev returns true if Exp is exactly zero
     */
    function isZeroExp(Exp memory _value) internal pure returns (bool) {
        return _value.mantissa == 0;
    }

    function safe224(
        uint256 _n,
        string memory _errorMessage
    ) internal pure returns (uint224) {
        require(_n < 2 ** 224, _errorMessage);
        return uint224(_n);
    }

    function safe32(
        uint256 _n,
        string memory _errorMessage
    ) internal pure returns (uint32) {
        require(_n < 2 ** 32, _errorMessage);
        return uint32(_n);
    }

    function add_(
        Exp memory _a,
        Exp memory _b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: add_(_a.mantissa, _b.mantissa)});
    }

    function add_(
        Double memory _a,
        Double memory _b
    ) internal pure returns (Double memory) {
        return Double({mantissa: add_(_a.mantissa, _b.mantissa)});
    }

    function add_(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a + _b;
    }

    function sub_(
        Exp memory _a,
        Exp memory _b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: sub_(_a.mantissa, _b.mantissa)});
    }

    function sub_(
        Double memory _a,
        Double memory _b
    ) internal pure returns (Double memory) {
        return Double({mantissa: sub_(_a.mantissa, _b.mantissa)});
    }

    function sub_(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a - _b;
    }

    function mul_(
        Exp memory _a,
        Exp memory _b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: mul_(_a.mantissa, _b.mantissa) / expScale});
    }

    function mul_(
        Exp memory _a,
        uint256 _b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: mul_(_a.mantissa, _b)});
    }

    function mul_(uint256 _a, Exp memory _b) internal pure returns (uint256) {
        return mul_(_a, _b.mantissa) / expScale;
    }

    function mul_(
        Double memory _a,
        Double memory _b
    ) internal pure returns (Double memory) {
        return Double({mantissa: mul_(_a.mantissa, _b.mantissa) / doubleScale});
    }

    function mul_(
        Double memory _a,
        uint256 _b
    ) internal pure returns (Double memory) {
        return Double({mantissa: mul_(_a.mantissa, _b)});
    }

    function mul_(
        uint256 _a,
        Double memory _b
    ) internal pure returns (uint256) {
        return mul_(_a, _b.mantissa) / doubleScale;
    }

    function mul_(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a * _b;
    }

    function div_(
        Exp memory _a,
        Exp memory _b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: div_(mul_(_a.mantissa, expScale), _b.mantissa)});
    }

    function div_(
        Exp memory _a,
        uint256 _b
    ) internal pure returns (Exp memory) {
        return Exp({mantissa: div_(_a.mantissa, _b)});
    }

    function div_(uint256 _a, Exp memory _b) internal pure returns (uint256) {
        return div_(mul_(_a, expScale), _b.mantissa);
    }

    function div_(
        Double memory _a,
        Double memory _b
    ) internal pure returns (Double memory) {
        return
            Double({
                mantissa: div_(mul_(_a.mantissa, doubleScale), _b.mantissa)
            });
    }

    function div_(
        Double memory _a,
        uint256 _b
    ) internal pure returns (Double memory) {
        return Double({mantissa: div_(_a.mantissa, _b)});
    }

    function div_(
        uint256 _a,
        Double memory _b
    ) internal pure returns (uint256) {
        return div_(mul_(_a, doubleScale), _b.mantissa);
    }

    function div_(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a / _b;
    }

    function fraction(
        uint256 _a,
        uint256 _b
    ) internal pure returns (Double memory) {
        return Double({mantissa: div_(mul_(_a, doubleScale), _b)});
    }
}

