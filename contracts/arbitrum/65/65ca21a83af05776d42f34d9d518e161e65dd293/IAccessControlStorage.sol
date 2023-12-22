// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

abstract contract IAccessControlStorage {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PRIZE_MANAGER_ROLE = keccak256("PRIZE_MANAGER_ROLE");

    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    function _roles(bytes32 role) internal view virtual returns (RoleData storage);
}
