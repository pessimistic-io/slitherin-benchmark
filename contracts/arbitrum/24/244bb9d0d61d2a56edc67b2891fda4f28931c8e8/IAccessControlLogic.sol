// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAccessControlLogic - AccessControlLogic interface
interface IAccessControlLogic {
    // =========================
    // Events
    // =========================

    /// @dev Emitted when ownership of a vault is transferred.
    /// @param oldOwner Address of the previous owner.
    /// @param newOwner Address of the new owner.
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    /// @dev Emitted when a new `role` is granted to an `account`.
    /// @param role Identifier for the role.
    /// @param account Address of the account.
    /// @param sender Address of the sender granting the role.
    event RoleGranted(bytes32 role, address account, address sender);

    /// @dev Emitted when a `role` is revoked from an `account`.
    /// @param role Identifier for the role.
    /// @param account Address of the account.
    /// @param sender Address of the sender revoking the role.
    event RoleRevoked(bytes32 role, address account, address sender);

    /// @dev Emitted when a cross chain logic flag is setted.
    /// @param flag Cross chain flag new value.
    event CrossChainLogicInactiveFlagSet(bool flag);

    // =========================
    // Main functions
    // =========================

    /// @notice Initializes the `creator` and `vaultId`.
    /// @param creator Address of the vault creator.
    /// @param vaultId ID of the vault.
    function initializeCreatorAndId(address creator, uint16 vaultId) external;

    /// @notice Returns the address of the creator of the vault and its ID.
    /// @return The creator's address and the vault ID.
    function creatorAndId() external view returns (address, uint16);

    /// @notice Returns the owner's address of the vault.
    /// @return Address of the vault owner.
    function owner() external view returns (address);

    /// @notice Retrieves the address of the Vault proxyAdmin.
    /// @return Address of the Vault proxyAdmin.
    function getVaultProxyAdminAddress() external view returns (address);

    /// @notice Transfers ownership of the proxy vault to a `newOwner`.
    /// @param newOwner Address of the new owner.
    function transferOwnership(address newOwner) external;

    /// @notice Updates the activation status of the cross-chain logic.
    /// @dev Can only be called by an authorized admin to enable or disable the cross-chain logic.
    /// @param newValue The new activation status to be set; `true` to activate, `false` to deactivate.
    function setCrossChainLogicInactiveStatus(bool newValue) external;

    /// @notice Checks whether the cross-chain logic is currently active.
    /// @dev Returns true if the cross-chain logic is active, false otherwise.
    /// @return isActive The current activation status of the cross-chain logic.
    function crossChainLogicIsActive() external view returns (bool isActive);

    /// @notice Checks if an `account` has been granted a particular `role`.
    /// @param role Role identifier to check.
    /// @param account Address of the account to check against.
    /// @return True if the account has the role, otherwise false.
    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);

    /// @notice Grants a specified `role` to an `account`.
    /// @dev The caller must be the owner of the vault.
    /// @dev Emits a {RoleGranted} event if the account hadn't been granted the role.
    /// @param role Role identifier to grant.
    /// @param account Address of the account to grant the role to.
    function grantRole(bytes32 role, address account) external;

    /// @notice Revokes a specified `role` from an `account`.
    /// @dev The caller must be the owner of the vault.
    /// @dev Emits a {RoleRevoked} event if the account had the role.
    /// @param role Role identifier to revoke.
    /// @param account Address of the account to revoke the role from.
    function revokeRole(bytes32 role, address account) external;

    /// @notice An account can use this to renounce a `role`, effectively losing its privileges.
    /// @dev Useful in scenarios where an account might be compromised.
    /// @dev Emits a {RoleRevoked} event if the account had the role.
    /// @param role Role identifier to renounce.
    function renounceRole(bytes32 role) external;
}

