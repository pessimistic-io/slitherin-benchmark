// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IChainlinkAggregator.sol";

contract OracleWrapper {
	uint8 private constant DECIMALS = 8; 
	IChainlinkAggregator public immutable ethOracle;
	IChainlinkAggregator public immutable underlyingOracle;

	constructor(address _ethOracle, address _underlyingOracle) public {
		ethOracle = IChainlinkAggregator(_ethOracle);
		underlyingOracle = IChainlinkAggregator(_underlyingOracle);
	}

	function latestAnswer() external view returns (int256) {
		int256 ethPricInUSD = ethOracle.latestAnswer();
		int256 underlyingPriceInETH = underlyingOracle.latestAnswer();
		return underlyingPriceInETH * ethPricInUSD / 10 ** 18;
	}

	function latestTimestamp() external view returns (uint256) {
		return underlyingOracle.latestTimestamp();
	}

	function decimals() external view returns (uint8) {
		return DECIMALS;
	}
}
