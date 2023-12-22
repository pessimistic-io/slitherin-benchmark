// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IOwnable} from "./IOwnable.sol";

/// @title IVaultFactory - VaultFactory Interface
/// @notice This contract is a vault factory that implements methods for creating new vaults
/// and updating them via the UpgradeLogic contract.
interface IVaultFactory is IOwnable {
    // =========================
    // Storage
    // =========================

    /// @notice The address of the immutable contract to which the `vault` call will be
    /// delegated if the call is made from `ProxyAdmin's` address.
    function upgradeLogic() external view returns (address);

    /// @notice The address from which the call to `vault` will delegate it to the `updateLogic`.
    function vaultProxyAdmin() external view returns (address);

    // =========================
    // Events
    // =========================

    /// @notice Emits when the new `vault` has been created.
    /// @param creator The creator of the created vault
    /// @param vault The address of the created vault
    /// @param vaultId The unique identifier for the vault (for `creator` address)
    event VaultCreated(
        address indexed creator,
        address indexed vault,
        uint16 vaultId
    );

    // =========================
    // Errors
    // =========================

    /// @notice Thrown if an attempt is made to initialize the contract a second time.
    error VaultFactory_AlreadyInitialized();

    /// @notice Thrown when a `creator` attempts to create a vault using
    /// a version of the implementation that doesn't exist.
    error VaultFactory_VersionDoesNotExist();

    /// @notice Thrown when a `creator` tries to create a vault with an `vaultId`
    /// that's already in use.
    /// @param creator The address which tries to create the vault.
    /// @param vaultId The id that is already used.
    error VaultFactory_IdAlreadyUsed(address creator, uint16 vaultId);

    /// @notice Thrown when a `creator` attempts to create a vault with an vaultId == `0`
    /// or when the `creator` address is the same as the `proxyAdmin`.
    error VaultFactory_InvalidDeployArguments();

    /// @dev Error to be thrown when an unauthorized operation is attempted.
    error VaultFactory_NotAuthorized();

    // =========================
    // Admin methods
    // =========================

    /// @notice Sets the address of the Ditto Bridge Receiver contract.
    /// @dev This function can only be called by an authorized admin.
    /// @param _dittoBridgeReceiver The address of the new Ditto Bridge Receiver contract.
    function setBridgeReceiverContract(address _dittoBridgeReceiver) external;

    // =========================
    // Vault implementation logic
    // =========================

    /// @notice Adds a `newImplemetation` address to the list of implementations.
    /// @param newImplemetation The address of the new implementation to be added.
    ///
    /// @dev Only callable by the owner of the contract.
    /// @dev After adding, the new implementation will be at the last index
    /// (i.e., version is `_implementations.length`).
    function addNewImplementation(address newImplemetation) external;

    /// @notice Retrieves the implementation address for a given `version`.
    /// @param version The version number of the desired implementation.
    /// @return impl_ The address of the specified implementation version.
    ///
    /// @dev If the `version` number is greater than the length of the `_implementations` array
    /// or the array is empty, `VaultFactory_VersionDoesNotExist` error is thrown.
    function implementation(uint256 version) external view returns (address);

    /// @notice Returns the total number of available implementation versions.
    /// @return The total count of versions in the `_implementations` array.
    function versions() external view returns (uint256);

    // =========================
    // Main functions
    // =========================

    /// @notice Computes the address of a `vault` deployed using `deploy` method.
    /// @param creator The address of the creator of the vault.
    /// @param vaultId The id of the vault.
    /// @dev `creator` and `id` are part of the salt for the `create2` opcode.
    function predictDeterministicVaultAddress(
        address creator,
        uint16 vaultId
    ) external view returns (address predicted);

    /// @notice Deploys a new `vault` based on a specified `version`.
    /// @param version The version number of the vault implementation to which
    ///        the new vault will delegate.
    /// @param vaultId A unique identifier for deterministic vault creation.
    ///        Used in combination with `msg.sender` for `create2` salt.
    /// @return The address of the newly deployed `vault`.
    ///
    /// @dev Uses the `create2` opcode for deterministic address generation based on a salt that
    /// combines the `msg.sender` and `vaultId`.
    /// @dev If the given `version` number is greater than the length of  the `_implementations`
    /// array or if the array is empty, it reverts with `VaultFactory_VersionDoesNotExist`.
    /// @dev If `vaultId` is zero, it reverts with`VaultFactory_InvalidDeployArguments`.
    /// @dev If the `vaultId` has already been used for the `msg.sender`, it reverts with
    /// `VaultFactory_IdAlreadyUsed`.
    function deploy(uint256 version, uint16 vaultId) external returns (address);

    function crossChainDeploy(
        address creator,
        uint256 version,
        uint16 vaultId
    ) external returns (address);
}

