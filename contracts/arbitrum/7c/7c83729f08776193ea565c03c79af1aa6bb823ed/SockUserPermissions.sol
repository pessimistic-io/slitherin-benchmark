// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./SockRegistryAccessManager.sol";
import "./ISockUserPermissions.sol";
import "./ISockFunctionRegistry.sol";

/**
 * @title SockUserPermissions
 * @dev Contract module that provides the ability for the user to delegate specific permissions to the sock owner
 * This is intended to allow sock to execute specific functions on behalf of the user.
 * Permissions are only settable by the owner.
 * @notice SockUserPermissions is only intended to be inherited by SockAccount do not use with other contracts.
 */
abstract contract SockUserPermissions is SockRegistryAccessManager, ISockUserPermissions {

    /// @dev UserPermission struct to store the allowed and payable properties of a function.
    mapping(uint256 => uint8) private _userPermissions;

    /// @dev Whether the user permissions have been initialized or not.
    /// This allows Sock to set permissions on deploy.
    bool internal _permissionsInitialized;

    /// @dev emitted when a user permission is set.
    event UserPermissionSet(uint256 indexed permissionIndex, bool allowed, bool isPayable);


    /**
     * @dev Sets the user permission for given permission indexs,
     * @param permissionIndexs The indexes of the functions in the sock function registry.
     * @param alloweds Whether the functions are allowed or not.
     * @param isPayables Whether the functions are payable or not.
     */
    function setUserPermissions(uint256[] memory permissionIndexs, bool[] memory alloweds, bool[] memory isPayables) external onlyOwner {
        require(permissionIndexs.length == alloweds.length && permissionIndexs.length == isPayables.length, "Permission indexs, alloweds, and isPayable lengths must match");
        for (uint256 i = 0; i < permissionIndexs.length;) {
            _setUserPermission(permissionIndexs[i], alloweds[i], isPayables[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Gets the user permission for a given permission index,
    /// @param permissionIndex The index of the function in the sock function registry.
    /// @return The user permission object.
    function getUserPermission(uint256 permissionIndex) public view returns (UserPermission memory) {
        uint8 permissions = _userPermissions[permissionIndex];
        bool allowed = (permissions & 1) == 1;  // checks the first bit
        bool isPayable = (permissions & 2) == 2;
        return UserPermission(allowed, isPayable);
    }

    /// @dev Sets the user permission for a given permission index
    /// @param permissionIndex The index of the function in the sock function registry.
    /// @param allowed Whether the function is allowed or not.
    /// @param isPayable Whether the function is payable or not.
    function _setUserPermission(uint256 permissionIndex, bool allowed, bool isPayable) internal {
        uint8 permissions;
        if (allowed) {
            permissions |= 1;  // sets the first bit
        }
        if (isPayable) {
            permissions |= 2;  // sets the second bit
        }
        _userPermissions[permissionIndex] = permissions;
        emit UserPermissionSet(permissionIndex, allowed, isPayable);
    }

    /// @dev Checks if a function is allowed to be called by Sock Owner.
    /// @param dest The to address of a transaction.
    /// @param func The calldata of a transaction.
    /// @param value The value of a transaction.
    function _requireOnlyAllowedFunctions(address dest, bytes calldata func, uint256 value) internal view {
        require(address(sockFunctionRegistry()) != address(0), "Sock function registry not set");
        ISockFunctionRegistry.AllowedFunctionInfo memory sockFunctionInfo = sockFunctionRegistry().getSockPermissionInfo(dest, func);
        UserPermission memory userPermission = getUserPermission(sockFunctionInfo.permissionIndex);
        if (value > 0) {
            _checkPayability(sockFunctionInfo, userPermission);
        } else {
            _checkPermission(sockFunctionInfo, userPermission);
        }
    }

    /// @dev Checks if a function is payable by Sock Owner.
    /// @param sockPermission The PermissionInfo object from the sock function registry
    /// @param userPermission The UserPermission object from the user permission mapping
    function _checkPayability(ISockFunctionRegistry.AllowedFunctionInfo memory sockPermission, UserPermission memory userPermission) internal pure {
        require(sockPermission.isPayable && userPermission.isPayable, "Function is not payable");
    }

    /// @dev Checks if a function is allowed by Sock Owner.
    /// @param sockPermission The PermissionInfo object from the sock function registry
    /// @param userPermission The UserPermission object from the user permission mapping
    function _checkPermission(ISockFunctionRegistry.AllowedFunctionInfo memory sockPermission, UserPermission memory userPermission) internal pure {
        require(sockPermission.allowed && userPermission.allowed, "Function is not allowed");
    }

}

