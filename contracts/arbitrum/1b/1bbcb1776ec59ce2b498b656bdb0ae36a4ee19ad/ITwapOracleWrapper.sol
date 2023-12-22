// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

interface ITwapOracleWrapper {
	error UniswapFailedToGetPrice();

	event TwapChanged(uint32 newTwap);
	event OracleAdded(address indexed token, address pool);
	event OracleRemoved(address indexed token);

	/**
	 * @notice getTokenPriceInETH returns the value of the token in ETH
	 * @dev {_twapPeriodInSeconds} cannot be zero, recommended value is 1800 (30 minutes)
	 * @param _token the address of the token
	 * @param _twapPeriodInSeconds the amount of seconds you want to go back
	 * @return The value of the token in ETH
	 */
	function getTokenPriceInETH(address _token, uint32 _twapPeriodInSeconds)
		external
		view
		returns (uint256);

	/**
	 * @notice getETHPrice returns the value of ETH in USD from chainlink
	 * @return Value in USD
	 */
	function getETHPrice() external view returns (uint256);
}

