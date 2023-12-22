// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { OwnableInternal } from "./OwnableInternal.sol";
import { AccessControlInternal } from "./AccessControlInternal.sol";
import { IAccessControlAdmin } from "./IAccessControlAdmin.sol";

contract AccessControlAdmin is IAccessControlAdmin, OwnableInternal, AccessControlInternal {
    function grantAdminRole(address admin) external override onlyOwner {
        _grantRole(ADMIN_ROLE, admin);
    }

    function grantSignerRole(address signer) external onlyRole(ADMIN_ROLE) {
        _grantRole(SIGNER_ROLE, signer);
    }
}

