// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./draft-IERC20Permit.sol";

/// @title Counterfeit Money is just as good as "real" money
/// @dev ERC20 Token with dynamic supply, supporting EIP-2612 signatures for token approvals
interface ICounterfeitMoney is IERC20, IERC20Permit {
	/// @notice Prints and sends a certain amount of CounterfeitMoney to an user
	/// @dev Emits an Transfer event from zero-address
	/// @param to The address receiving the freshly printed money
	/// @param amount The amount of money that will be printed
	function print(address to, uint256 amount) external;

	/// @notice Burns and removes an approved amount of CounterfeitMoney from an user
	/// @dev Emits an Transfer event to zero-address
	/// @param from The address losing the CounterfeitMoney
	/// @param amount The amount of money that will be removed from the account
	function burn(address from, uint256 amount) external;
}

