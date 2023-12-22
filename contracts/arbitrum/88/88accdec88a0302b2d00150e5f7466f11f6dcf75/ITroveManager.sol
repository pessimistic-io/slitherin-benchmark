// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITroveManager {
	function liquidateTroves(address _asset, uint256 _n) external;

	function getCurrentICR(
		address _asset,
		address _borrower,
		uint256 _price
	) external view returns (uint256);
}


