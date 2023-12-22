// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { AccessControl as OZAccessControl } from "./AccessControl.sol";
import { Strings } from "./Strings.sol";
import { CoreAccessControl, CoreAccessControlConfig } from "./CoreAccessControl.sol";
import { CoreStopGuardian } from "./CoreStopGuardian.sol";

abstract contract BaseAccessControl is CoreAccessControl, CoreStopGuardian {
    /**
     * @dev
     * Modifiers inherited from CoreAccessControl:
     * onlyDefinitive
     * onlyClients
     * onlyWhitelisted
     * onlyClientAdmin
     * onlyDefinitiveAdmin
     *
     * Modifiers inherited from CoreStopGuardian:
     * stopGuarded
     */

    constructor(CoreAccessControlConfig memory coreAccessControlConfig) CoreAccessControl(coreAccessControlConfig) {}

    /**
     * @dev Inherited from CoreStopGuardian
     */
    function enableStopGuardian() public override onlyAdmins {
        return _enableStopGuardian();
    }

    /**
     * @dev Inherited from CoreStopGuardian
     */
    function disableStopGuardian() public override onlyClientAdmin {
        return _disableStopGuardian();
    }
}

