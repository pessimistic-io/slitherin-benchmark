// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
 * @param tokens should have the same array of coins from the curve pool
 * @param uint8 holds the decimals of each tokens
 * @param underlying is the curve pool uses underlying
 */
struct PoolConfig {
	address[] tokens;
	string get_dy_signature;
	string exchange_signature;
}

