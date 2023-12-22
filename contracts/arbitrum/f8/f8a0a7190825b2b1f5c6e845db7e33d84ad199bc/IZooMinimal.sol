// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

/// @title IZooMinimal
/// @author Koala Money
interface IZooMinimal {
	/// @notice Allows controller to update distribution and user information.
	///
	/// @notice _owner The address of the user to update.
	function sync(address _owner) external;

	/// @notice Gets the informations about the account owner by `_owner`.
	///
	/// @param _owner The address of the account to query.
	///
	/// @return totalDeposit The amount of native token deposited
	/// @return totalDebt Total amount of debt left
	function userInfo(address _owner) external view returns (uint256 totalDeposit, int256 totalDebt);
}

