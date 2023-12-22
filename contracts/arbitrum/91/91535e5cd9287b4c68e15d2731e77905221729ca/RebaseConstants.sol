// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

library RebaseConstants {
    uint256 internal constant CHANGE_PRECISION = 100_000_000;
    uint256 internal constant MAX_CHANGE = CHANGE_PRECISION / 10; // 10%
    uint256 internal constant MAX_INCREASE = CHANGE_PRECISION + MAX_CHANGE;
    uint256 internal constant MAX_DECREASE = CHANGE_PRECISION - MAX_CHANGE;
    uint256 internal constant MIN_DURATION = 1 hours;
}

