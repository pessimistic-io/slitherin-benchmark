//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

contract Constant {
    uint256 public constant WATER_DEFAULT_PRICE = 1_000_000;
    uint256 public constant CONVERT_PRECISION = 1e6;
    uint256 public constant MAX_BPS = 100_000;
    uint256 public constant COOLDOWN_PERIOD = 3 days;
    uint256 internal constant RATE_PRECISION = 1e30;
    uint8 public constant VLP_DECIMAL = 18;
}

