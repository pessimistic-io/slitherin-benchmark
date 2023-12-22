// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

interface IERC20Callback {
	/// @notice receiveERC20 should be used as the "receive" callback of native token but for erc20
	/// @dev Be sure to limit the access of this call.
	/// @param _token transfered token
	/// @param _value The value of the transfer
	function receiveERC20(address _token, uint256 _value) external;
}

