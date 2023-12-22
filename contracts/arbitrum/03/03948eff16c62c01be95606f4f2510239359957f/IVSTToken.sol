// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IVSTToken {
	function mint(
		address _asset,
		address _account,
		uint256 _amount
	) external;

	function burn(address _account, uint256 _amount) external;

	function sendToPool(
		address _sender,
		address poolAddress,
		uint256 _amount
	) external;

	function returnFromPool(
		address poolAddress,
		address user,
		uint256 _amount
	) external;
}


