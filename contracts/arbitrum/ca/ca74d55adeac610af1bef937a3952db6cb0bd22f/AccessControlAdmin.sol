// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { OwnableInternal } from "./OwnableInternal.sol";
import { AccessControlInternal } from "./AccessControlInternal.sol";
import { IAccessControlAdmin } from "./IAccessControlAdmin.sol";

contract AccessControlAdmin is IAccessControlAdmin, OwnableInternal, AccessControlInternal {
    function grantAdminRole(address admin) external override onlyOwner {
        _grantRole(ADMIN_ROLE, admin);
    }

    function grantPauserRole(address pauser) external onlyRole(ADMIN_ROLE) {
        _grantRole(PAUSER_ROLE, pauser);
    }

    function grantRevenueRole(address collector) external onlyRole(ADMIN_ROLE) {
        _grantRole(REVENUE_ROLE, collector);
    }

    function grantEmergencyRole(address emergency) external onlyRole(ADMIN_ROLE) {
        _grantRole(EMERGENCY_ROLE, emergency);
    }
}

