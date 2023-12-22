// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import { Math } from "./Math.sol";

/// @dev Implements simple signed fixed point math add, sub, mul and div operations.
library IntMath {
    /// @dev Returns 1 in the fixed point representation, with `decimals` decimals.
    function unit(uint8 decimals) internal pure returns (int256) {
        return int256(10**uint256(decimals));
    }

    function toUint(int256 x) internal pure returns (uint256) {
        return uint256(abs(x));
    }

    function abs(int256 x) internal pure returns (uint256) {
        uint256 t = 0;
        if (x < 0) {
            t = uint256(0 - x);
        } else {
            t = uint256(x);
        }
        return t;
    }

    /// @dev Multiplies x and y, assuming they are both fixed point with 18 digits.
    function mulD(int256 x, int256 y) internal pure returns (int256) {
        return mulD(x, y, 18);
    }

    /// @dev Multiplies x and y, assuming they are both fixed point with `decimals` digits.
    function mulD(
        int256 x,
        int256 y,
        uint8 decimals
    ) internal pure returns (int256) {
        if (x == 0 || y == 0) {
            return 0;
        }
        if (x * y < 0) {
            return int256(Math.mulDiv(abs(x), abs(y), 10**uint256(decimals))) * (-1);
        } else {
            return int256(Math.mulDiv(abs(x), abs(y), 10**uint256(decimals)));
        }
    }

    /// @dev Divides x between y, assuming they are both fixed point with 18 digits.
    function divD(int256 x, int256 y) internal pure returns (int256) {
        return divD(x, y, 18);
    }

    /// @dev Divides x between y, assuming they are both fixed point with `decimals` digits.
    function divD(
        int256 x,
        int256 y,
        uint8 decimals
    ) internal pure returns (int256) {
        if (x == 0 || y == 0) {
            return 0;
        }
        if (x * y < 0) {
            return int256(Math.mulDiv(abs(x), 10**uint256(decimals), abs(y))) * (-1);
        } else {
            return int256(Math.mulDiv(abs(x), 10**uint256(decimals), abs(y)));
        }
    }
}

