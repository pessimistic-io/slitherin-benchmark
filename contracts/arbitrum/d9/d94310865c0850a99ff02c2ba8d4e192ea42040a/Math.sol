// SPDX-License-Identifier: MIT
pragma solidity 0.8;

library Math {
    function diff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function interpolate(uint256 firstValue, uint256 secondValue, uint256 numerator, uint256 denominator)
        internal
        pure
        returns (uint256)
    {
        uint256 difference = diff(firstValue, secondValue);
        difference = difference * numerator / denominator;
        return firstValue < secondValue ? firstValue + difference : firstValue - difference;
    }
}

