// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IJonesGlpVaultRouter {
	function stableWithdrawalSignal(
		uint256 _shares,
		bool _compound
	) external returns (uint256);

	function depositGlp(
		uint256 _assets,
		address _sender,
		bool _compound
	) external returns (uint256);

	function depositStable(
		uint256 _assets,
		bool _compound,
		address _user
	) external returns (uint256);

	function claimRewards() external returns (uint256, uint256, uint256);

	function redeemGlpAdapter(
		uint256 _shares,
		bool _compound,
		address _token,
		address _user,
		bool _native
	) external returns (uint256);

	function redeemStable(uint256 _epoch) external returns (uint256);

	function currentEpoch() external view returns (uint256);

	function convertToAssets(
		uint256 shares
	) external view returns (uint256 assets);

	function convertToShares(
		uint256 assets
	) external view returns (uint256 shares);
}

