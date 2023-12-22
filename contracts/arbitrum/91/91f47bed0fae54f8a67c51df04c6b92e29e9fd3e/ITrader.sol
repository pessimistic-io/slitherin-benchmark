// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ITrader {
	error InvalidRequestEncoding();
	error AmountInAndOutAreZeroOrSameValue();

	/**
	 * exchange Execute a swap request
	 * @param receiver the wallet that will receives the outcome token
	 * @param _request the encoded request
	 */
	function exchange(address receiver, bytes memory _request)
		external
		returns (uint256 swapResponse_);

	/**
	 * getAmountIn get what your need for almost-exact amount in.
	 * @dev depending of the trader, some aren't exact but higher depending of the slippage
	 * @param _request the encoded request of InOutParams
	 */
	function getAmountIn(bytes memory _request) external view returns (uint256);

	/**
	 * getAmountOut get what your need for exact amount out.
	 * @param _request the encoded request of InOutParams
	 */
	function getAmountOut(bytes memory _request) external view returns (uint256);
}

