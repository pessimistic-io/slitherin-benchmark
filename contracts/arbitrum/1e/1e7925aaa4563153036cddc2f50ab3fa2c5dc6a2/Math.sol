// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Math {
    function diff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function interpolate(uint256 a, uint256 b, uint256 numerator, uint256 denominator)
        internal
        pure
        returns (uint256)
    {
        uint256 difference = diff(a, b);
        difference = difference * numerator / denominator;
        return a < b ? a + difference : a - difference;
    }
}

