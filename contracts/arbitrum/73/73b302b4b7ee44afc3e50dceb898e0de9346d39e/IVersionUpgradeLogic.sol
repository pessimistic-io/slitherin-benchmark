// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title IVersionUpgradeLogic - VersionUpgradeLogic interface
interface IVersionUpgradeLogic {
    // =========================
    // Events
    // =========================

    /// @notice Emits when the implementation address is changed.
    /// @param newImplementation The address of the new implementation.
    event ImplementationChanged(address newImplementation);

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when an `owner` attempts to update a vault using
    /// a version of the implementation that doesn't exist.
    error VersionUpgradeLogic_VersionDoesNotExist();

    /// @notice Thrown when there's an attempt to update the vault to its
    /// current implementation address.
    error VersionUpgradeLogic_CannotUpdateToCurrentVersion();

    // =========================
    // Main functions
    // =========================

    /// @notice Initiates the upgrade process to a new vault version.
    /// @dev This function can only be called by vault to upgrade the vault to the specified version.
    /// @param vaultVersion The version number of the implementation in the factory to which the upgrade will be performed.
    function upgradeVersion(uint256 vaultVersion) external;
}

