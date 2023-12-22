// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import { IWhitelist } from "./IWhitelist.sol";

import { AdminAccessControl } from "./AdminAccessControl.sol";

import "./Errors.sol";
import { Sets } from "./Sets.sol";

/// @title  Whitelist
/// @author Alchemix Finance
contract Whitelist is IWhitelist, AdminAccessControl {
	using Sets for Sets.AddressSet;
	Sets.AddressSet private addresses;

	/// @inheritdoc IWhitelist
	bool public override disabled;

	/// @notice Indicates that the whitelist has been disabled.
	error Disabled();

	/// @inheritdoc IWhitelist
	function getAddresses() external view returns (address[] memory) {
		return addresses.values;
	}

	/// @inheritdoc IWhitelist
	function add(address caller) external override {
		_onlyAdmin();
		if (disabled) {
			revert Disabled();
		}
		addresses.add(caller);
		emit AccountAdded(caller);
	}

	/// @inheritdoc IWhitelist
	function remove(address caller) external override {
		_onlyAdmin();
		if (disabled) {
			revert Disabled();
		}
		addresses.remove(caller);
		emit AccountRemoved(caller);
	}

	/// @inheritdoc IWhitelist
	function disable() external override {
		_onlyAdmin();
		disabled = true;
		emit WhitelistDisabled();
	}

	/// @inheritdoc IWhitelist
	function isWhitelisted(address account) external view override returns (bool) {
		return disabled || addresses.contains(account);
	}
}

