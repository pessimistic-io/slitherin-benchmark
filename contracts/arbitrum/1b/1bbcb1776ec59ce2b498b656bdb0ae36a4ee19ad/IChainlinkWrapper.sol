// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import { Aggregators } from "./ChainlinksModels.sol";

interface IChainlinkWrapper {
	event OracleAdded(
		address indexed token,
		address priceAggregator,
		address indexAggregator
	);

	event OracleRemoved(address indexed token);

	/**
	 * @notice getAggregators returns the price and index aggregator used for a token
	 * @param _token the token address
	 * @return Aggregators structure
	 */
	function getAggregators(address _token) external view returns (Aggregators memory);
}

