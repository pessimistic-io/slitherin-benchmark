// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.7;

import { OracleAnswer } from "./OracleModels.sol";

interface IOracleWrapper {
	error TokenIsNotRegistered(address _token);
	error ResponseFromOracleIsInvalid(address _token, address _oracle);

	/**
	 * @notice getPrice get the current and last price with the last update
	 * @dev Depending of the wrapper and the oracle, last price and last update might be faked.
	 *      If faked: they will use the currentPrice and block.timestamp
	 * @dev If the contract fails to get the price, it will returns an empty response.
	 * @param _token the address of the token
	 * @return answer_ OracleAnswer structure.
	 */
	function getPrice(address _token)
		external
		view
		returns (OracleAnswer memory answer_);
}

