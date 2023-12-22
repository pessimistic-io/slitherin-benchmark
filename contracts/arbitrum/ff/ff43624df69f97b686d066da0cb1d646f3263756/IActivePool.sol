// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IActivePool {
	function sendAsset(
		address _asset,
		address _account,
		uint256 _amount
	) external;

	function decreaseVSTDebt(address _asset, uint256 _amount) external;
}


