// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ITroveManager {
	function getCurrentICR(
		address _asset,
		address _borrower,
		uint256 _price
	) external view returns (uint256);

	function getTroveStatus(address _asset, address _borrower)
		external
		view
		returns (uint256);
}


