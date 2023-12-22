// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SafeERC20.sol";

interface ISwap {
	struct Swap {
		// variables around the ramp management of A,
		// the amplification coefficient * n * (n - 1)
		// see https://www.curve.fi/stableswap-paper.pdf for details
		uint256 initialA;
		uint256 futureA;
		uint256 initialATime;
		uint256 futureATime;
		// fee calculation
		uint256 swapFee;
		uint256 adminFee;
		IERC20 lpToken;
		// contract references for all tokens being pooled
		IERC20[] pooledTokens;
		// multipliers for each pooled token's precision to get to POOL_PRECISION_DECIMALS
		// for example, TBTC has 18 decimals, so the multiplier should be 1. WBTC
		// has 8, so the multiplier should be 10 ** 18 / 10 ** 8 => 10 ** 10
		uint256[] tokenPrecisionMultipliers;
		// the pool balance of each token, in the token's precision
		// the contract's actual token balance might differ
		uint256[] balances;
	}

	function swapStorage() external returns (Swap memory);

	function swapVirtualToAsset(
		uint256 _dx,
		uint256 _minDx,
		uint256 _deadline,
		address _receiver
	) external returns (uint256 dy);

	function swapAssetToVirtual(
		uint256 _dx,
		uint256 _deadline
	) external returns (uint256 dy);

	function addLiquidity(
		uint256 amount,
		uint256 deadline
	) external returns (uint256);

	function removeLiquidity(
		uint256 amount,
		uint256 deadline
	) external returns (uint256 recovered);

	function migrate() external;

	function getAssetBalance() external view returns (uint256);

	function getVirtualLpBalance() external view returns (uint256);

	function calculateSwap(
		uint8 tokenIndexFrom,
		uint8 tokenIndexTo,
		uint256 dx
	) external view returns (uint256);

	function calculateVirtualToAsset(
		uint256 dx
	) external view returns (uint256 dy);

	function calculateAssetToVirtual(
		uint256 dx
	) external view returns (uint256 dy);
}

