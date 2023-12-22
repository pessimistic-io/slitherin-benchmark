// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/// @title Interface for WETH9
interface IWETH9 {
	/// @notice Deposit ether to get wrapped ether
	function deposit() external payable;

	/// @notice Withdraw :amount: of wrapped ether
	/// @param amount - amount of wrapped ether to witdraw back to ether
	function withdraw(uint256 amount) external;
}

