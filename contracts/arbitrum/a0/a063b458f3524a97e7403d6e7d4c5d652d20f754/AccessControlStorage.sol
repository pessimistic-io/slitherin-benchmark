// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

library AccessControlStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.standard.access.roles");

    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    struct Layout {
        mapping(bytes32 => RoleData) roles;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

