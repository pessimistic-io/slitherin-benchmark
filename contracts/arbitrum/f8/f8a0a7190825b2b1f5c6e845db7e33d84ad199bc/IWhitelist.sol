// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

/// @title  Whitelist
/// @author Alchemix Finance
interface IWhitelist {
	/// @notice Emitted when a contract is added to the whitelist.
	///
	/// @param account The account that was added to the whitelist.
	event AccountAdded(address account);

	/// @notice Emitted when a contract is removed from the whitelist.
	///
	/// @param account The account that was removed from the whitelist.
	event AccountRemoved(address account);

	/// @notice Emitted when the whitelist is deactivated.
	event WhitelistDisabled();

	/// @notice Returns the list of addresses that are whitelisted for the given contract address.
	///
	/// @return addresses The addresses that are whitelisted to interact with the given contract.
	function getAddresses() external view returns (address[] memory addresses);

	/// @notice Returns the disabled status of a given whitelist.
	///
	/// @return disabled A flag denoting if the given whitelist is disabled.
	function disabled() external view returns (bool);

	/// @notice Adds an contract to the whitelist.
	///
	/// @param caller The address to add to the whitelist.
	function add(address caller) external;

	/// @notice Adds a contract to the whitelist.
	///
	/// @param caller The address to remove from the whitelist.
	function remove(address caller) external;

	/// @notice Disables the whitelist of the target whitelisted contract.
	///
	/// This can only occur once. Once the whitelist is disabled, then it cannot be reenabled.
	function disable() external;

	/// @notice Checks that the `msg.sender` is whitelisted when it is not an EOA.
	///
	/// @param account The account to check.
	///
	/// @return whitelisted A flag denoting if the given account is whitelisted.
	function isWhitelisted(address account) external view returns (bool);
}

