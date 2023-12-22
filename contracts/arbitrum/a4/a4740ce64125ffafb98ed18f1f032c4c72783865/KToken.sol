// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { ERC20 } from "./ERC20.sol";

import { AdminAccessControl } from "./AdminAccessControl.sol";
import "./Errors.sol";

/// @title KToken
/// @author Koala Money
///
/// @notice Koala utility token usd.
contract KToken is AdminAccessControl, ERC20 {
	/// @notice The identifier of the role which allows accounts to mint tokens.
	bytes32 public constant SENTINEL_ROLE = keccak256("SENTINEL");

	/// @notice The identifier of the role which can mint tokens.
	bytes32 public constant MINTER_ROLE = keccak256("MINTER");

	/// @notice The addresses paused from minting new tokens.
	mapping(address => bool) public paused;

	constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

	/// @notice Pauses or unpauses the minting right for `_minter`
	///
	/// @notice Reverts with an {OnlySentinelAllowed} error if the caller is missing the sentinel role.
	///
	/// @param _minter The address of the minter.
	/// @param _state The state of minting right for `_minter`.
	function pauseMinter(address _minter, bool _state) external {
		_onlySentinel();
		paused[_minter] = _state;
		emit Paused(_minter, _state);
	}

	/// @notice Mints tokens to a recipient.
	///
	/// @notice Reverts with an {OnlyMinterAllowed} error if the caller is missing the minter role.
	/// @notice Reverts with an {MinterPaused} error if the minter is in pause state.
	///
	/// @param _recipient The address of the recipient of the minted tokens.
	/// @param _amount The amount of tokens to mint.
	function mint(address _recipient, uint256 _amount) external {
		_onlyMinter();
		_checkNotPaused();
		_mint(_recipient, _amount);
	}

	/// @notice Burns `_amount` of tokens from the caller.
	///
	/// @param _amount The amount of tokens to burn.
	function burn(uint256 _amount) external {
		_burn(msg.sender, _amount);
	}

	/// @notice Burns `_amount` tokens from `_owner`, deducting from the caller's allowance
	///
	/// @notice Reverts if the caller does not have allowance for `_owner` of at least `_amount`
	///
	/// @param _owner The address of the account whom tokens will be destroyed.
	/// @param _amount The amount of tokens to destroy.
	function burnFrom(address _owner, uint256 _amount) external {
		_spendAllowance(_owner, msg.sender, _amount);
		_burn(_owner, _amount);
	}

	function _onlySentinel() internal view {
		if (!hasRole(SENTINEL_ROLE, msg.sender)) {
			revert OnlySentinelAllowed();
		}
	}

	function _onlyMinter() internal view {
		if (!hasRole(MINTER_ROLE, msg.sender)) {
			revert OnlyMinterAllowed();
		}
	}

	function _checkNotPaused() internal view {
		if (paused[msg.sender]) {
			revert MinterPaused();
		}
	}

	event Paused(address minter, bool isPaused);

	error OnlyMinterAllowed();

	error OnlySentinelAllowed();

	error MinterPaused();
}

