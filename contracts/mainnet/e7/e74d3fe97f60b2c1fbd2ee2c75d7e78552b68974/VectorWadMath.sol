// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./SignedMath.sol";
import "./Math.sol";

library VectorWadMath {
    using Math for uint256;
    using SignedMath for int256;

    int256 constant PRECISION = 1e18;
    int256 constant PRECISION_UINT = 1e18;

    function distance(
        int256 x1,
        int256 y1,
        int256 x2,
        int256 y2
    ) internal pure returns (uint256) {
        return ((x2 - x1).abs()**2 + (y2 - y1).abs()**2).sqrt();
    }

    function unitVector(
        int256 x1,
        int256 y1,
        int256 x2,
        int256 y2
    ) internal pure returns (int256, int256) {
        int256 dist = int256(distance(x1, y1, x2, y2));
        return (((x2 - x1) * PRECISION) / dist, ((y2 - y1) * PRECISION) / dist);
    }

    function scaleVector(
        int256 x1,
        int256 y1,
        int256 x2,
        int256 y2,
        int256 scale
    ) internal pure returns (int256, int256) {
        return (
            x1 + ((x2 - x1) * scale) / PRECISION,
            y1 + ((y2 - y1) * scale) / PRECISION
        );
    }
}

