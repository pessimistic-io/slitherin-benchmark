// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlLib} from "./AccessControlLib.sol";
import {Constants} from "./Constants.sol";

/// @title BaseContract
/// @notice A base contract that provides common access control features.
/// @dev This contract integrates with AccessControlLib to provide role-based access
/// control and ownership checks. Contracts inheriting from this can use its modifiers
/// for common access restrictions.
contract BaseContract {
    // =========================
    // Error
    // =========================

    /// @notice Thrown when an account is not authorized to perform a specific action.
    error UnauthorizedAccount(address account);

    // =========================
    // Modifiers
    // =========================

    /// @dev Modifier that checks if an account has a specific `role`
    /// or is the owner of the contract.
    /// @dev Reverts with `UnauthorizedAccount` error if the conditions are not met.
    modifier onlyRoleOrOwner(bytes32 role) {
        _checkRole(role, msg.sender);

        _;
    }

    /// @dev Modifier that checks if an account is the contract's owner.
    /// @dev Reverts with `UnauthorizedAccount` error if neither conditions are met.
    modifier onlyOwner() {
        _checkOnlyOwner(msg.sender);

        _;
    }

    /// @dev Modifier that checks if an account is the contract's address itself.
    /// @dev Reverts with `UnauthorizedAccount` error if neither conditions are met.
    modifier onlyVaultItself() {
        _checkOnlyVaultItself(msg.sender);

        _;
    }

    /// @dev Modifier that checks if an account is the contract's owner
    /// or the contract's address itself.
    /// @dev Reverts with `UnauthorizedAccount` error if neither conditions are met.
    modifier onlyOwnerOrVaultItself() {
        _checkOnlyOwnerOrVaultItself(msg.sender);

        _;
    }

    // =========================
    // Internal function
    // =========================

    /// @dev Checks if the given `account` possesses the specified `role` or is the owner.
    /// @dev Reverts with `UnauthorizedAccount` error if neither conditions are met.
    /// @param role The role to check against the account.
    /// @param account The account to check.
    function _checkRole(bytes32 role, address account) internal view virtual {
        AccessControlLib.RolesStorage storage s = AccessControlLib
            .rolesStorage();

        if (
            !((msg.sender == AccessControlLib.getOwner()) ||
                _hasRole(s, role, account))
        ) {
            revert UnauthorizedAccount(account);
        }
    }

    /// @dev Checks if the given `account` is the contract's address itself.
    /// @dev Reverts with `UnauthorizedAccount` error if neither conditions are met.
    /// @param account The account to check.
    function _checkOnlyVaultItself(address account) internal view virtual {
        if (account != address(this)) {
            revert UnauthorizedAccount(account);
        }
    }

    /// @dev Checks if the given `account` is the contract's address itself.
    /// @dev Reverts with `UnauthorizedAccount` error if neither conditions are met.
    /// @param account The account to check.
    function _checkOnlyOwnerOrVaultItself(
        address account
    ) internal view virtual {
        if (account == address(this)) {
            return;
        }

        if (account != AccessControlLib.getOwner()) {
            revert UnauthorizedAccount(account);
        }
    }

    /// @dev Checks if the given `account` is the owner of the contract.
    /// @dev Reverts with `UnauthorizedAccount` error if neither conditions are met.
    /// @param account The account to check.
    function _checkOnlyOwner(address account) internal view virtual {
        if (account != AccessControlLib.getOwner()) {
            revert UnauthorizedAccount(account);
        }
    }

    /// @dev Returns `true` if `account` has been granted `role`.
    /// @param s The storage reference for roles from AccessControlLib.
    /// @param role The role to check against the account.
    /// @param account The account to check.
    /// @return True if the account possesses the role, false otherwise.
    function _hasRole(
        AccessControlLib.RolesStorage storage s,
        bytes32 role,
        address account
    ) internal view returns (bool) {
        return s.roles[role][account];
    }
}

