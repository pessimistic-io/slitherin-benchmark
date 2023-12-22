// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8;

library SafeCast {
    // Safely casts uint256 to uint128.
    function toUint128(uint256 a) internal pure returns (uint128) {
        require(a <= type(uint128).max, "OVERFLOW");
        return uint128(a);
    }
}

