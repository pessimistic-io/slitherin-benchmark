// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import { CustomOracle } from "./CustomOracleModels.sol";

interface ICustomOracleWrapper {
	event OracleAdded(address indexed _token, address _externalOracle);
	event OracleRemoved(address indexed _token);

	/**
	 * @notice getOracle returns the configured info of the custom oracle
	 * @param _token the address of the token
	 * @return CustomOracle structure
	 */
	function getOracle(address _token) external view returns (CustomOracle memory);
}

