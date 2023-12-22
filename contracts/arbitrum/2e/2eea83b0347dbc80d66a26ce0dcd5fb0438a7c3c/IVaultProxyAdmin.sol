// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IVaultFactory} from "./IVaultFactory.sol";

/// @title IVaultProxyAdmin - VaultProxyAdmin interface.
/// @notice This contract is a common proxy admin for all vaults deployed via factory.
/// @dev Through this contract, all vaults can be updated to a new implementation.
interface IVaultProxyAdmin {
    // =========================
    // Storage
    // =========================

    function vaultFactory() external view returns (IVaultFactory);

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when an anyone other than the address of the factory tries calling the method.
    error VaultProxyAdmin_CallerIsNotFactory();

    /// @notice Thrown when a non-owner of the vault tries to update its implementation.
    error VaultProxyAdmin_SenderIsNotVaultOwner();

    /// @notice Thrown when an `owner` attempts to update a vault using
    /// a version of the implementation that doesn't exist.
    error VaultProxyAdmin_VersionDoesNotExist();

    /// @notice Thrown when there's an attempt to update the vault to its
    /// current implementation address.
    error VaultProxyAdmin_CannotUpdateToCurrentVersion();

    // =========================
    // Vault implementation logic
    // =========================

    /// @notice Sets the `vault` implementation to an address from the factory.
    /// @param vault Address of the vault to be upgraded.
    /// @param implementation The new implementation from the factory.
    /// @dev Can only be called from the vault factory.
    function initializeImplementation(
        address vault,
        address implementation
    ) external;

    /// @notice Updates the `vault` implementation to an address from the factory.
    /// @param vault Address of the vault to be upgraded.
    /// @param version The version number of the new implementation from the `_implementations` array.
    ///
    /// @dev This function can only be called by the owner of the vault.
    /// @dev The version specified should be an existing version in the factory
    /// and must not be the current implementation of the vault.
    /// @dev If the function caller is not the owner of the vault, it reverts with
    /// `VaultProxyAdmin_SenderIsNotVaultOwner`.
    /// @dev If the specified `version` number is outside the valid range of the implementations
    /// or is zero, it reverts with `VaultProxyAdmin_VersionDoesNotExist`.
    /// @dev If the specified version  is the current implementation, it reverts
    /// with `VaultProxyAdmin_CannotUpdateToCurrentVersion`.
    function upgrade(address vault, uint256 version) external;
}

