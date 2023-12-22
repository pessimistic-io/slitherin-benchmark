// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IJonesUsdcVault {
	function tvl() external view returns (uint256);

	function convertToAssets(
		uint256 shares
	) external view returns (uint256 assets);

	function convertToShares(
		uint256 assets
	) external view returns (uint256 shares);
}

