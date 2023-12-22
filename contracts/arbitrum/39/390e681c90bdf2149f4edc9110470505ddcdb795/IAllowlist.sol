// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Errors.sol";
import "./Sets.sol";

/// @title  Allowlist
/// @author Savvy DeFi
interface IAllowlist {
    /// @dev Emitted when a contract is added to the allowlist.
    ///
    /// @param account The account that was added to the allowlist.
    event AccountAdded(address account);

    /// @dev Emitted when a contract is removed from the allowlist.
    ///
    /// @param account The account that was removed from the allowlist.
    event AccountRemoved(address account);

    /// @dev Emitted when the allowlist is deactivated.
    event AllowlistDisabled();

    /// @dev Returns the list of addresses that are allowlisted for the given contract address.
    ///
    /// @return addresses The addresses that are allowlisted to interact with the given contract.
    function getAddresses() external view returns (address[] memory addresses);

    /// @dev Returns the disabled status of a given allowlist.
    ///
    /// @return disabled A flag denoting if the given allowlist is disabled.
    function disabled() external view returns (bool);

    /// @dev Adds an contract to the allowlist.
    ///
    /// @param caller The address to add to the allowlist.
    function add(address caller) external;

    /// @dev Adds a contract to the allowlist.
    ///
    /// @param caller The address to remove from the allowlist.
    function remove(address caller) external;

    /// @dev Disables the allowlist of the target allowlisted contract.
    ///
    /// This can only occur once. Once the allowlist is disabled, then it cannot be reenabled.
    function disable() external;

    /// @dev Checks that the `msg.sender` is allowlisted when it is not an EOA.
    ///
    /// @param account The account to check.
    ///
    /// @return allowlisted A flag denoting if the given account is allowlisted.
    function isAllowed(address account) external view returns (bool);
}

