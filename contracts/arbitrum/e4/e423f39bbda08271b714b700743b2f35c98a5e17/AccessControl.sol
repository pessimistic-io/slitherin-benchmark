// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { Context } from "./Context.sol";

import { AccessControlInternal } from "./AccessControlInternal.sol";
import { IAccessControl } from "./IAccessControl.sol";

contract AccessControl is AccessControlInternal, IAccessControl {
    function grantRole(bytes32 role, address account) public virtual override onlyRole(_getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual onlyRole(_getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) public virtual override {
        _renounceRole(role, account);
    }

    function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
        return _hasRole(role, account);
    }

    function getRoleAdmin(bytes32 role) public view virtual override returns (bytes32) {
        return _getRoleAdmin(role);
    }
}

