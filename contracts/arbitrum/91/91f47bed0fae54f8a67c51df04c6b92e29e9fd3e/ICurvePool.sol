// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ICurvePool {
	function coins(uint256 arg) external view returns (address);

	function get_dy_underlying(
		int128 i,
		int128 j,
		uint256 dx
	) external view returns (uint256);

	function calc_withdraw_one_coin(uint256 _burn, int128 i)
		external
		view
		returns (uint256);

	function exchange(
		int128 i,
		int128 j,
		uint256 _dx,
		uint256 _min_dy,
		address _receiver
	) external returns (uint256);

	function exchange_underlying(
		int128 i,
		int128 j,
		uint256 _dx,
		uint256 _min_dy,
		address _receiver
	) external returns (uint256);
}

