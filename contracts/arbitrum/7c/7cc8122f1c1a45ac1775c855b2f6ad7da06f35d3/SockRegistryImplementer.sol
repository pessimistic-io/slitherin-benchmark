// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "./SockRegistryAccessManager.sol";
import "./ISockFunctionRegistry.sol";

/**
 * @title SockRegistryImplementer
 * @dev Contract module that provides a mechanism to check whether a function is allowed based on the SockFunctionRegistry.
 * It extends the SockRegistryAccessManager which provides access control mechanisms for the sock function registry.
 */
contract SockRegistryImplementer is SockRegistryAccessManager {

    /**
     * @notice Checks whether a function call is allowed based on the SockFunctionRegistry.
     * @dev Based on the value sent with the function and the `isSock` flag, the function checks the appropriate
     * sock function registry to determine if the function is allowed.
     * @param dest The address of the contract where the function is intended to be executed.
     * @param func The function selector.
     * @param value The ether value sent with the function.
     * @param isSock Indicates whether the function relates to sock functionalities.
     */
    function _requireOnlyAllowedFunctions(
        address dest,
        bytes calldata func,
        uint256 value,
        bool isSock
    ) internal view {
        if (address(sockFunctionRegistry()) != address(0)) {
            bool allowed;
            // If ether is being sent with the function:
            if (value > 0) {
                // Check the registry for payable functions based on the `isSock` flag.
                allowed = isSock ? sockFunctionRegistry().isAllowedPayableSockFunction(dest, func)
                                : sockFunctionRegistry().isAllowedPayableFunction(dest, func);
            } else {
                // Check the registry for non-payable functions based on the `isSock` flag.
                allowed = isSock ? sockFunctionRegistry().isAllowedSockFunction(dest, func)
                                : sockFunctionRegistry().isAllowedFunction(dest, func);
            }
            // If the function isn't allowed, revert the transaction.
            require(allowed, "Only allowed functions");
        }
    }
}

