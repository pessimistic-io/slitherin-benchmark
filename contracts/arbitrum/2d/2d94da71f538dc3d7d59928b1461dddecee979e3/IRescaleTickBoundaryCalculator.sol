// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRescaleTickBoundaryCalculator {
    function verifyAndGetNewRescaleTickBoundary(
        bool wasInRange,
        int24 lastRescaleTick,
        address strategyAddress,
        address controllerAddress
    )
        external
        view
        returns (bool allowRescale, int24 newTickUpper, int24 newTickLower);
}

