// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import { Oracle } from "./OracleModels.sol";

interface IPriceFeed {
	event OracleAdded(
		address indexed token,
		address primaryWrappedOracle,
		address secondaryWrappedOracle
	);
	event OracleRemoved(address indexed token);
	event OracleVerificationChanged(address indexed newVerificator);
	event OracleDisabledStateChanged(address indexed token, bool isDisabled);

	event TokenPriceUpdated(address indexed token, uint256 price);
	event AccessChanged(address indexed token, bool hasAccess);

	error OracleDisabled();
	error OracleDown();
	error OracleNotFound();
	error UnsupportedToken();

	/**
	 * @notice fetchPrice returns the safest price
	 * @param _token the address of the token
	 */
	function fetchPrice(address _token) external returns (uint256);

	/**
	 * @notice getOracle will return the configuration for the token
	 * @param _token the address of the token
	 * @return oracle_ Oracle strcuture
	 */
	function getOracle(address _token) external view returns (Oracle memory);

	/**
	 * @notice isOracleDisabled will return the disabled state of the oracle
	 * @param _token the address of the token
	 * @return disabled_ The disabled state
	 */
	function isOracleDisabled(address _token) external view returns (bool);

	/**
	 * @notice getLastUsedPrice returns the last price used by the system
	 * @dev This should never be used! This is informative usage only
	 * @param _token the address of the token
	 * @return lastPrice_ last price used by the protocol
	 */
	function getLastUsedPrice(address _token) external view returns (uint256);

	/**
	 * @notice getExternalPrice returns the current price without any checks
	 * @dev secondary oracle can be null, in this case, the value will be zero
	 * @param _token address of the token
	 * @return answers_ [primary oracle price, secondary oracle price]
	 */
	function getExternalPrice(address _token)
		external
		view
		returns (uint256[2] memory);
}

