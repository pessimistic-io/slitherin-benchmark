// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Math.sol";
import "./SignedWadMath.sol";

function wadSigmoid(int256 x) pure returns (uint256) {
    return uint256(unsafeWadDiv(1e18, 1e18 + wadExp(-x)));
}

function random(uint256 seed, uint256 max) pure returns (uint256) {
    return uint256(keccak256(abi.encodePacked(seed))) % max;
}

function sampleCircle(uint256 seed, uint256 radius)
    pure
    returns (int256 x, int256 y)
{
    unchecked {
        seed = uint256(keccak256(abi.encodePacked(seed)));
        int256 r = int256(random(seed++, radius)) + 1;
        int256 xUnit = int256(random(seed++, 2e18)) - 1e18;
        int256 yUnit = int256(Math.sqrt(1e36 - uint256(xUnit * xUnit)));
        x = int256((xUnit * r) / 1e18);
        y = int256((yUnit * r) / 1e18);
        if (random(seed, 2) == 0) {
            y = -y;
        }
    }
}

function sampleInvSqrt(uint256 seed, uint256 e) pure returns (uint256) {
    return wadInvSqrt(random(seed, 1e18), e) / 2;
}

function wadInvSqrt(uint256 x, uint256 e) pure returns (uint256) {
    return Math.sqrt(1e54 / (e + x));
}

