// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./AccessControlUpgradeable.sol";

abstract contract AccessControlRolesUpgradeable is AccessControlUpgradeable {
    /// @dev An Owner controls all roles and can upgrade the contract.
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    /// @dev An Admin controls Operators and may configure the system.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @dev An Operator may call routine functions to keep the system working.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    modifier onlyOwner() {
        bool hasAccess = hasRole(OWNER_ROLE, msg.sender);
        require(hasAccess, "AccessControl: not owner");
        _;
    }

    modifier onlyAdmin() {
        bool hasAccess = (hasRole(ADMIN_ROLE, msg.sender) ||
            hasRole(OWNER_ROLE, msg.sender));
        require(hasAccess, "AccessControl: not admin");
        _;
    }

    modifier onlyOperator() {
        bool hasAccess = (hasRole(OPERATOR_ROLE, msg.sender) ||
            hasRole(ADMIN_ROLE, msg.sender) ||
            hasRole(OWNER_ROLE, msg.sender));
        require(hasAccess, "AccessControl: not operator");
        _;
    }

    function _setupRoles() internal {
        __AccessControl_init();
        _setupRole(OWNER_ROLE, msg.sender);
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(ADMIN_ROLE, OWNER_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
    }
}

