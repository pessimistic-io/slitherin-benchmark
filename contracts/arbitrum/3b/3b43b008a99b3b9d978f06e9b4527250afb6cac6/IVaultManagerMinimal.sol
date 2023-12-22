// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

/// @title IVaultAdapter
/// @author Koala Money
interface IVaultManagerMinimal {
	/// @notice Deposits funds into the vault
	///
	/// @param _amount The amount of funds to deposit
	function deposit(uint256 _amount) external;

	/// @notice Withdraw `_amount` of tokens from the vaults and send the withdrawn tokens to `_recipient`.
	///
	/// @param _recipient The address of the recipient of the funds.
	/// @param _amount    The amount of funds to requested.
	function withdraw(address _recipient, uint256 _amount) external;
}

