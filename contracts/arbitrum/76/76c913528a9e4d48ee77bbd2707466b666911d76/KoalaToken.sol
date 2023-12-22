// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ERC20 } from "./ERC20.sol";

import { AdminAccessControl } from "./AdminAccessControl.sol";
import "./Errors.sol";

/// @title KoalaToken
/// @author Koala Money
///
/// @notice The Koala Token.
contract KoalaToken is ERC20, AdminAccessControl {
	/// @notice The identifier of the role that can mint tokens.
	bytes32 public constant MINTER_ROLE = keccak256("MINTER");

	/// @notice The maximum total supply.
	uint256 public constant MAX_SUPPLY = 400_000_000 ether;

	constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

	/// @notice Mints `_amount` of tokens to `_recipient`
	///
	/// @notice Reverts with an {OnlyMinterAllowed} error if the caller is missing the minter role.
	/// @notice Reverts with an {MaxSupplyBreached} error if the total supply is greater than the defined max supply after the mint operation.
	///
	/// @param _recipient The address of the recipient of the minted tokens.
	/// @param _amount The amount of tokens to mint.
	function mint(address _recipient, uint256 _amount) external {
		_onlyMinter();

		if (_recipient == address(0)) {
			revert ZeroAddress();
		}
		// Checks if supply is still under max supply allowed
		uint256 _totalSupply = totalSupply();
		if (_totalSupply + _amount > MAX_SUPPLY) {
			revert MaxSupplyBreached();
		}

		_mint(_recipient, _amount);
	}

	function _onlyMinter() internal view {
		if (!hasRole(MINTER_ROLE, msg.sender)) {
			revert OnlyMinterAllowed();
		}
	}

	error OnlyMinterAllowed();

	error MaxSupplyBreached();
}

