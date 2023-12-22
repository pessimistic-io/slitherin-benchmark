// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./ISockFunctionRegistry.sol";
import "./SockOwnable.sol";

/* solhint-disable private-variables */

/**
 * @title SockRegistryAccessManager
 * @dev Contract module that provides access control mechanisms over the sock function registry.
 * The contract introduces the concept of a sock owner and is an extension of the SockOwnable module.
 * Only the sock owner can change the sock function registry.
 * @notice SockRegistryAccessManager is only intended to be inherited by SockAccount do not use with other contracts.
 */
contract SockRegistryAccessManager is SockOwnable {

    // Reference to the sock function registry interface.
    ISockFunctionRegistry internal _sockFunctionRegistry;

    // Event emitted when the sock function registry is changed.
    event SockFunctionRegistryChanged(address oldSockFunctionRegistry, address sockFunctionRegistry);

    /**
     * @notice Sets a new sock function registry.
     * @dev Only the owner can call this function.
     * @param aSockFunctionRegistry The address of the new sock function registry.
     */
    function setSockFunctionRegistry(ISockFunctionRegistry aSockFunctionRegistry) external onlyOwner {
        _transferSockFunctionRegistry(aSockFunctionRegistry);
    }

    /**
     * @notice Returns the address of the current sock function registry.
     * @return The address of the current sock function registry.
     */
    function sockFunctionRegistry() public view returns (ISockFunctionRegistry) {
        return _sockFunctionRegistry;
    }

    /**
     * @notice Internal function to transfer the sock function registry.
     * @param newSockFunctionRegistry The address of the new sock function registry.
     */
    function _transferSockFunctionRegistry(ISockFunctionRegistry newSockFunctionRegistry) internal {
        address oldSockFunctionRegistry = address(_sockFunctionRegistry);
        _sockFunctionRegistry = newSockFunctionRegistry;
        emit SockFunctionRegistryChanged(oldSockFunctionRegistry, address(newSockFunctionRegistry));
    }
}

