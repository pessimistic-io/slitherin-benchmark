// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/// @title Safe cast functions
library SafeCast {
    error SafeCast_Int128Overflow(uint128 value);

    function toInt128(uint128 y) internal pure returns (int128 z) {
        unchecked {
            if (y >= 2**127) revert SafeCast_Int128Overflow(y);
            z = int128(y);
        }
    }

    error SafeCast_Int256Overflow(uint256 value);

    function toInt256(uint256 y) internal pure returns (int256 z) {
        unchecked {
            if (y >= 2**255) revert SafeCast_Int256Overflow(y);
            z = int256(y);
        }
    }

    error SafeCast_UInt224Overflow(uint256 value);

    function toUint224(uint256 y) internal pure returns (uint224 z) {
        if (y > 2**224) revert SafeCast_UInt224Overflow(y);
        z = uint224(y);
    }
}

