// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";

contract ExtendedAccessControlUpgradeable is AccessControlUpgradeable {
    /// @custom:storage-location erc7201:fortesecurities.ExtendedAccessControlUpgradeable
    struct ExtendedAccessControlUpgradeableStorage {
        bytes32[] roles;
    }

    // keccak256(abi.encode(uint256(keccak256("fortesecurities.ExtendedAccessControlUpgradeable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ExtendedAccessControlUpgradeableStorageLocation =
        0x19b29a04048f51eb9591acef31c8d25631a0f178287c237da958990d82c90400;

    function _getExtendedAccessControlUpgradeableStorage()
        private
        pure
        returns (ExtendedAccessControlUpgradeableStorage storage $)
    {
        assembly {
            $.slot := ExtendedAccessControlUpgradeableStorageLocation
        }
    }

    function __ExtendedAccessControl_init() internal initializer {
        __ExtendedAccessControl_init_unchained();
    }

    function __ExtendedAccessControl_init_unchained() internal initializer {
        _addRole(DEFAULT_ADMIN_ROLE);
    }

    /**
     * @dev Returns the list of roles.
     * @return bytes32[] List of roles.
     */
    function roles() public view returns (bytes32[] memory) {
        ExtendedAccessControlUpgradeableStorage storage $ = _getExtendedAccessControlUpgradeableStorage();
        return $.roles;
    }

    /**
     * @dev Adds a role to the list of roles.
     * @param role Role to be added.
     */
    function _addRole(bytes32 role) internal {
        ExtendedAccessControlUpgradeableStorage storage $ = _getExtendedAccessControlUpgradeableStorage();
        $.roles.push(role);
    }

    /**
     * @dev Grants all roles to a specified address.
     * @param _address Address to be granted roles.
     */
    function _grantRoles(address _address) internal {
        bytes32[] memory _roles = roles();
        for (uint256 i = 0; i < _roles.length; i++) {
            _grantRole(_roles[i], _address);
        }
    }

    /**
     * @dev Grants all roles to a specified address.
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     * @param _address Address to be granted roles.
     */
    function grantRoles(address _address) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRoles(_address);
    }

    /**
     * @dev Revokes all roles from a specified address.
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     * @param _address Address to be revoked roles.
     */
    function revokeRoles(address _address) public onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32[] memory _roles = roles();
        for (uint256 i = 0; i < _roles.length; i++) {
            _revokeRole(_roles[i], _address);
        }
    }

    /**
     * @dev Revokes all roles held by `from` account, and grants those roles to `to` account
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     * @param from Address to be revoked roles.
     * @param to Address to be granted roles.
     */
    function transferRoles(address from, address to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32[] memory _roles = roles();
        for (uint256 i = 0; i < _roles.length; i++) {
            bytes32 role = _roles[i];
            if (hasRole(role, from)) {
                _grantRole(role, to);
                _revokeRole(role, from);
            }
        }
    }

    /**
     * @dev Revokes all roles held by the sender, and grants those roles to `to` account
     * Can only be called by an account with the DEFAULT_ADMIN_ROLE.
     * @param to Address to be granted roles.
     */
    function transferRoles(address to) public onlyRole(DEFAULT_ADMIN_ROLE) {
        transferRoles(_msgSender(), to);
    }
}

