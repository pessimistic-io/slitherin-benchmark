// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Constants
/// @dev These constants can be imported and used by other contracts for consistency.
library Constants {
    /// @dev A keccak256 hash representing the executor role.
    bytes32 internal constant EXECUTOR_ROLE =
        keccak256("DITTO_WORKFLOW_EXECUTOR_ROLE");

    /// @dev A constant representing the native token in any network.
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
}

