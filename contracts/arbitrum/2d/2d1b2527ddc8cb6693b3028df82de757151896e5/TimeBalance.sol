// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.20;

import "./Math.sol";

library TimeBalance {
    uint256 constant TIME_MAX = type(uint32).max;
    uint256 constant TIME_MASK = TIME_MAX << 224;
    uint256 constant BALANCE_MAX = type(uint224).max;
    uint256 constant BALANCE_MASK = BALANCE_MAX;

    function merge(uint256 x, uint256 y) internal view returns (uint256 z) {
        unchecked {
            if (x == 0) {
                return y;
            }
            uint256 xTime = Math.max(block.timestamp, x >> 224);
            uint256 yTime = y >> 224;
            require(yTime <= xTime, "MATURITY_ORDER");
            uint256 yBalance = y & BALANCE_MASK;
            uint256 xBalance = x & BALANCE_MASK;
            uint256 zBalance = xBalance + yBalance;
            require(zBalance <= BALANCE_MAX, "NEW_BALANCE_OVERFLOW");
            return x + yBalance;
        }
    }

    function pack(uint256 balance, uint256 time) internal pure returns (uint256) {
        require(time <= type(uint32).max, "TIME_OVERFLOW");
        require(balance <= BALANCE_MAX, "BALANCE_OVERFLOW");
        return (time << 224) | balance;
    }

    function getBalance(uint256 x) internal pure returns (uint256) {
        return x & BALANCE_MASK;
    }

    function getTime(uint256 x) internal pure returns (uint256) {
        return x >> 224;
    }

    function split(uint256 z, uint256 yBalance) internal pure returns (uint256 x, uint256 y) {
        unchecked {
            uint256 zBalance = z & BALANCE_MASK;
            if (zBalance == yBalance) {
                return (0, z); // full transfer
            }
            require(zBalance > yBalance, "INSUFFICIENT_BALANCE");
            x = z - yBalance; // preserve the time
            y = (z & TIME_MASK) | yBalance;
        }
    }
}

