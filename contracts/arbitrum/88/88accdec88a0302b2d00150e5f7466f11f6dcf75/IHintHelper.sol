// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IHintHelper {
	function getLiquidatableAmount(
		address _asset,
		uint256 _assetPrice
	) external view returns (uint256);
}


