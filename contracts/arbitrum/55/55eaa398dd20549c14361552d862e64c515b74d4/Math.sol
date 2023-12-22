// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Math {
    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /**
     * @dev Convert value from srcDecimals to dstDecimals.
     */
    function convertDecimals(
        uint256 value,
        uint8 srcDecimals,
        uint8 dstDecimals
    ) internal pure returns (uint256 result) {
        if (srcDecimals == dstDecimals) {
            result = value;
        } else if (srcDecimals < dstDecimals) {
            result = value * (10**(dstDecimals - srcDecimals));
        } else {
            result = value / (10**(srcDecimals - dstDecimals));
        }
    }

    /**
     * @dev Convert value from srcDecimals to dstDecimals, rounded up.
     */
    function convertDecimalsCeil(
        uint256 value,
        uint8 srcDecimals,
        uint8 dstDecimals
    ) internal pure returns (uint256 result) {
        if (srcDecimals == dstDecimals) {
            result = value;
        } else if (srcDecimals < dstDecimals) {
            result = value * (10**(dstDecimals - srcDecimals));
        } else {
            uint256 temp = 10**(srcDecimals - dstDecimals);
            result = value / temp;
            if (value % temp != 0) {
                result += 1;
            }
        }
    }
}

