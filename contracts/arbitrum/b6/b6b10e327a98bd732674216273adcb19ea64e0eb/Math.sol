// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

// a library for performing various math operations

library Math {
    uint256 public constant WAD = 1e18;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant halfRAY = RAY / 2;

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y >> (1 + 1);
            while (x < z) {
                z = x;
                x = (y / x + x) >> 1;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    //rounds to zero if x*y < WAD / 2
    function wmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return ((x * y) + (WAD >> 1)) / WAD;
    }

    function uoperation(
        uint256 x,
        uint256 y,
        bool addOperation
    ) internal pure returns (uint256 z) {
        if (addOperation) {
            return uadd(x, y);
        } else {
            return usub(x, y);
        }
    }

    /// @dev Subtracts two unsigned 256 bit integers together and returns the result.
    ///
    /// @dev This operation is checked and will fail if the result overflows.
    ///
    /// @param x The first operand.
    /// @param y The second operand.
    ///
    /// @return z the result.
    function usub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (x < y) {
            return 0;
        }
        z = x - y;
    }

    /// @dev Adds two unsigned 256 bit integers together and returns the result.
    ///
    /// @dev This operation is checked and will fail if the result overflows.
    ///
    /// @param x The first operand.
    /// @param y The second operand.
    ///
    /// @return z The result.
    function uadd(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
    }

    /// @notice Return minimum uint256 value.
    /// @param x The first operand.
    /// @param y The second operand.
    /// @return z The result
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? y : x;
    }

    /// @notice Return maximum uint256 value.
    /// @param x The first operand.
    /// @param y The second operand.
    /// @return z The result
    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? x : y;
    }

    /**
     * @dev Multiplies two ray, rounding half up to the nearest ray
     * @param a Ray
     * @param b Ray
     * @return The result of a*b, in ray
     **/
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        if (a > (type(uint256).max - halfRAY) / b) {
            return 0;
        }

        return (a * b + halfRAY) / RAY;
    }

    /**
     * @dev Divides two ray, rounding half up to the nearest ray
     * @param a Ray
     * @param b Ray
     * @return The result of a/b, in ray
     **/
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            return 0;
        }
        uint256 halfB = b / 2;

        if (a > (type(uint256).max - halfB) / RAY) {
            return 0;
        }

        return (a * RAY + halfB) / b;
    }

    /// @notice utility function to find weighted averages without any underflows or zero division problems.
    /// @dev use x to determine weights, with y being the values you're weighting
    /// @param valueToAdd new allotment amount
    /// @param currentValue current allotment amount
    /// @param weightToAdd new amount of y being added to weighted average
    /// @param currentWeight current weighted average of y
    /// @return Update duration
    function findWeightedAverage(
        uint256 valueToAdd,
        uint256 currentValue,
        uint256 weightToAdd,
        uint256 currentWeight
    ) internal pure returns (uint256) {
        uint256 totalWeight = weightToAdd + currentWeight;
        if (totalWeight == 0) {
            return 0;
        }
        uint256 totalValue = (valueToAdd * weightToAdd) +
            (currentValue * currentWeight);
        return totalValue / totalWeight;
    }
}

