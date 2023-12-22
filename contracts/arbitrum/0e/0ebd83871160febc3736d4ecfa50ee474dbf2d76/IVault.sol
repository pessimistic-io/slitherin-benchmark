// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IVault - Vault interface
/// @notice This interface defines the structure for a Vault contract.
/// @dev It provides function signatures and custom errors to be implemented by a Vault.
interface IVault {
    // =========================
    // Errors
    // =========================

    /// @notice Error to indicate that the function does not exist in the Vault.
    error Vault_FunctionDoesNotExist();

    /// @notice Error to indicate that invalid constructor data was provided.
    error Vault_InvalidConstructorData();

    // =========================
    // Main functions
    // =========================

    /// @notice Returns the address of the implementation of the Vault.
    /// @dev This is the address of the contract where the Vault delegates its calls to.
    /// @return implementationAddress The address of the Vault's implementation.
    function getImplementationAddress()
        external
        view
        returns (address implementationAddress);
}

