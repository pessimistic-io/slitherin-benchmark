// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IPriceFeed {
	/// @notice getExternalPrice gets external oracles price and update the storage value.
	/// @param _token the token you want to price. Needs to be supported by the wrapper.
	/// @return The current price reflected on the external oracle in 1e18 format.
	function getExternalPrice(address _token)
		external
		view
		returns (uint256);
}


