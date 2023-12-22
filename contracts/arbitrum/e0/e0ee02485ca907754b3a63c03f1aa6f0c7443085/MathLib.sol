// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

library MathLib {
    function max(uint256[] memory values) internal pure returns (uint256) {
        uint256 maxValue = values[0];
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] > maxValue) {
                maxValue = values[i];
            }
        }
        return maxValue;
    }

    function min(uint256[] memory values) internal pure returns (uint256) {
        uint256 minValue = values[0];
        for (uint256 i = 1; i < values.length; i++) {
            if (values[i] < minValue) {
                minValue = values[i];
            }
        }
        return minValue;
    }

    function subWithZeroFloor(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }
}

