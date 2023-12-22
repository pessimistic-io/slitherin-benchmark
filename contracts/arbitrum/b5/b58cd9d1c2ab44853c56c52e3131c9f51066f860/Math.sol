// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8;

library Math {
    // Returns abosolute difference of two numbers
    function diff(int24 a, int24 b) internal pure returns (uint24) {
        return a > b ? uint24(a - b) : uint24(b - a);
    }
}

