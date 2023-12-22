pragma solidity ^0.8.9;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SharwaFinance
 * Copyright (C) 2023 SharwaFinance
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import {Ownable} from "./Ownable.sol";
import {AccessControl} from "./AccessControl.sol";

contract RoleManager is Ownable, AccessControl {
    bytes32 public constant TRADER_ROLE = keccak256("TRADER_ROLE");

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(TRADER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    // EXTERNAL

    function changeRole(address value, bytes32 role, bool state) external {
        if (state) {
            grantRole(role, value);
        } else {
            revokeRole(role, value);
        }
    }

    // DEFAULT_ADMIN_ROLE

    function changeAdminRole(bytes32 role, bytes32 adminRole) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "msg.sender does not own the role");
        _setRoleAdmin(role, adminRole);
    }

    function renounceAdminRole(bytes32 role) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "msg.sender does not own the role");
        require(getRoleAdmin(role) == DEFAULT_ADMIN_ROLE, "non-default admin role");
        _setRoleAdmin(role, role);
    }
}
