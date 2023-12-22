// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

/**
 * @dev These are global constants used in the Unlimited protocol.
 * These constants are mainly used as multipliers.
 */

// 100 percent in BPS.
uint256 constant FULL_PERCENT = 100_00;
int256 constant FEE_MULTIPLIER = 1e14;
int256 constant FEE_BPS_MULTIPLIER = FEE_MULTIPLIER / 1e4; // 1e10
int256 constant BUFFER_MULTIPLIER = 1e6;
uint256 constant PERCENTAGE_MULTIPLIER = 1e6;
uint256 constant LEVERAGE_MULTIPLIER = 1_000_000;
uint8 constant ASSET_DECIMALS = 18;
uint256 constant ASSET_MULTIPLIER = 10 ** ASSET_DECIMALS;

// Rational to use 24 decimals for prices:
// 24 decimals is larger or equal than decimals of all important tokens. (Ethereum = 18, BNB = 18, USDT = 6)
// It is higher than most price feeds (Chainlink = 8, Uniswap = 18, Binance = 8)
uint256 constant PRICE_DECIMALS = 24;
uint256 constant PRICE_MULTIPLIER = 10 ** PRICE_DECIMALS;

