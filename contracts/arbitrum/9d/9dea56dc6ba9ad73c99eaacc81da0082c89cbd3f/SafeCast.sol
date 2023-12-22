// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

library SafeCast {
    function toUint128(uint256 v) internal pure returns (uint128) {
        require(v <= type(uint128).max, "SC: v must fit in 128 bits");

        return uint128(v);
    }

    function toUint64(uint256 v) internal pure returns (uint64) {
        require(v <= type(uint64).max, "SC: v must fit in 64 bits");

        return uint64(v);
    }
}

