// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./Kernel.sol";

import {ROLESv1, RolesConsumer} from "./OlympusRoles.sol";
import {Treasury, ERC20} from "./TRSRY.sol";
import {RADToken} from "./RADToken.sol";

contract JPow is Policy, RolesConsumer {
    // =========  EVENTS ========= //

    // =========  ERRORS ========= //

    // =========  STATE  ========= //
    RADToken public TOKEN;
    Treasury public TRSRY;

    constructor(Kernel _kernel) Policy(_kernel) {}

    //============================================================================================//
    //                                      POLICY SETUP                                          //
    //============================================================================================//
    function configureDependencies()
        external
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("TOKEN");
        dependencies[2] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        TOKEN = RADToken(getModuleAddress(dependencies[1]));
        TRSRY = Treasury(getModuleAddress(dependencies[2]));
    }

    function requestPermissions()
        external
        pure
        override
        returns (Permissions[] memory requests)
    {
        requests = new Permissions[](1);
        requests[0] = Permissions(
            toKeycode("TRSRY"),
            Treasury.withdraw.selector
        );
    }

    function transfer(
        ERC20 asset,
        address to,
        uint256 amount
    ) external onlyRole("admin") {
        TRSRY.withdraw(asset, amount);
        asset.transfer(to, amount);
    }

    function recoverToken(
        ERC20 asset,
        address to,
        uint256 amount
    ) external onlyRole("admin") {
        asset.transfer(to, amount);
    }
}

