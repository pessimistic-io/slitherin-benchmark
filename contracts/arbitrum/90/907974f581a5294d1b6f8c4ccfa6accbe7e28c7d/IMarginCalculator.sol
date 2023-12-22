// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IMarginCalculator {
	function getNakedMarginRequired(
		address _underlying,
		address _strike,
		address _collateral,
		uint256 _shortAmount,
		uint256 _strikePrice,
		uint256 _underlyingPrice,
		uint256 _shortExpiryTimestamp,
		uint256 _collateralDecimals,
		bool _isPut
	) external view returns (uint256);
}

