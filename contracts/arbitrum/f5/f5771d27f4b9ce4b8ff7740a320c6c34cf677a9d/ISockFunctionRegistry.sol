// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/**
 * Aggregated Signatures validator.
 */
interface ISockFunctionRegistry {

    /// @notice Information regarding allowed functions.
    struct AllowedFunctionInfo {
        bool isPayable;  // Whether the function is payable or not
        bool allowed;    // Whether the function is allowed or not
        uint256 permissionIndex; // Immutable index
    }

    function getSockPermissionInfo(
        address dest,
        bytes calldata func
    ) external view returns (AllowedFunctionInfo memory);
}

