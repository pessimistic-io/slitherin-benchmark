// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

library Constants {
    uint256 internal constant STABLE_ASSET_ID = 1;

    uint256 internal constant ONE = 1e18;

    // Reserve factor is 8%
    uint256 internal constant RESERVE_FACTOR = 8 * 1e16;

    // Reserve factor of LPToken is 4%
    uint256 internal constant LPT_RESERVE_FACTOR = 4 * 1e16;

    // Margin option
    int256 internal constant MIN_MARGIN_AMOUNT = 1e6;
    uint256 internal constant MARGIN_ROUNDED_DECIMALS = 1e4;

    uint256 internal constant MIN_PENALTY = 4 * 1e5;

    uint256 internal constant MIN_SQRT_PRICE = 79228162514264337593;
    uint256 internal constant MAX_SQRT_PRICE = 79228162514264337593543950336000000000;

    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;

    // 0.5%
    uint256 internal constant BASE_MIN_COLLATERAL_WITH_DEBT = 5000;
    // 0.00005
    uint256 internal constant MIN_COLLATERAL_WITH_DEBT_SLOPE = 50;
    // 1.6% scaled by 1e6
    uint256 internal constant BASE_LIQ_SLIPPAGE_SQRT_TOLERANCE = 12649;
    // 0.000022
    uint256 internal constant LIQ_SLIPPAGE_SQRT_SLOPE = 22;
    // 0.001
    uint256 internal constant LIQ_SLIPPAGE_SQRT_BASE = 1000;
    // 2.4% scaled by 1e6
    uint256 internal constant SLIPPAGE_SQRT_TOLERANCE = 15491;
}

