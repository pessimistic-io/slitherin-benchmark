// SPDX-License-Identifier:SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import { OracleAnswer } from "./OracleModels.sol";

interface IOracleVerificationV1 {
	/**
	 * @notice verify will check the answers and choose wisely between the primary, secondary or lastGoodPrice
	 * @param _lastGoodPrice the last price used by the protocol
	 * @param _oracleAnswers the answers from the primary and secondary oracle
	 * @return price the safest price
	 */
	function verify(uint256 _lastGoodPrice, OracleAnswer[2] calldata _oracleAnswers)
		external
		view
		returns (uint256);
}

