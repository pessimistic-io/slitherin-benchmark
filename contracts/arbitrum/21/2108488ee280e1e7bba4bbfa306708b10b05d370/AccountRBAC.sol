/*
Licensed under the Voltz v2 License (the "License"); you 
may not use this file except in compliance with the License.
You may obtain a copy of the License at

https://github.com/Voltz-Protocol/v2-core/blob/main/core/LICENSE
*/
pragma solidity >=0.8.19;

import "./SetUtil.sol";
import "./AddressError.sol";
import "./Periphery.sol";

/**
 * @title Object for tracking an accounts permissions (role based access control).
 */

library AccountRBAC {
    using SetUtil for SetUtil.Bytes32Set;
    using SetUtil for SetUtil.AddressSet;

    /**
     * @dev All permissions used by the system
     * need to be hardcoded here.
     */
    bytes32 internal constant _ADMIN_PERMISSION = "ADMIN";

    /**
     * @dev Thrown when a permission specified by a user does not exist or is invalid.
     */
    error InvalidPermission(bytes32 permission);

    struct Data {
        /**
         * @dev The owner of the account
         */
        address owner;
        /**
         * @dev Set of permissions for each address enabled by the account.
         */
        mapping(address => SetUtil.Bytes32Set) permissions;
        /**
         * @dev Array of addresses that this account has given permissions to.
         */
        SetUtil.AddressSet permissionAddresses;
    }

    /**
     * @dev Reverts if the specified permission is unknown to the account RBAC system.
     */
    function checkPermissionIsValid(bytes32 permission) internal pure {
        if (permission != AccountRBAC._ADMIN_PERMISSION) {
            revert InvalidPermission(permission);
        }
    }

    /**
     * @dev Sets the owner of the account.
     */
    function setOwner(Data storage self, address owner) internal {
        self.owner = owner;
    }

    /**
     * @dev Grants a particular permission to the specified target address.
     */
    function grantPermission(Data storage self, bytes32 permission, address target) internal {
        if (target == address(0)) {
            revert AddressError.ZeroAddress();
        }

        checkPermissionIsValid(permission);

        if (!self.permissionAddresses.contains(target)) {
            self.permissionAddresses.add(target);
        }

        self.permissions[target].add(permission);
    }

    /**
     * @dev Revokes a particular permission from the specified target address.
     */
    function revokePermission(Data storage self, bytes32 permission, address target) internal {
        checkPermissionIsValid(permission);

        self.permissions[target].remove(permission);

        if (self.permissions[target].length() == 0) {
            self.permissionAddresses.remove(target);
        }
    }

    /**
     * @dev Revokes all permissions for the specified target address.
     * @notice only removes permissions for the given address, not for the entire account
     */
    function revokeAllPermissions(Data storage self, address target) internal {
        bytes32[] memory permissions = self.permissions[target].values();

        if (permissions.length == 0) {
            return;
        }

        for (uint256 i = 0; i < permissions.length; i++) {
            self.permissions[target].remove(permissions[i]);
        }

        self.permissionAddresses.remove(target);
    }

    /**
     * @dev Returns wether the specified address has the given permission.
     */
    function hasPermission(Data storage self, bytes32 permission, address target) internal view returns (bool) {
        checkPermissionIsValid(permission);

        return target != address(0) && self.permissions[target].contains(permission);
    }

    /**
     * @dev Returns wether the specified target address has the given permission, or has the high level admin permission.
     */
    function authorized(Data storage self, bytes32 permission, address target) internal view returns (bool) {
        checkPermissionIsValid(permission);

        return (
            (target == self.owner) || hasPermission(self, _ADMIN_PERMISSION, target)
                || hasPermission(self, permission, target) || Periphery.isPeriphery(target)
        );
    }
}

