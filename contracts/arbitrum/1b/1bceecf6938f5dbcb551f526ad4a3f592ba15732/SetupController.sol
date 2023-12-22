// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPermissions} from "./IPermissions.sol";
import {Operations} from "./Operations.sol";

abstract contract SetupController {
    error SetUpUnauthorized(address collection, address account);

    modifier canSetUp(address collection) {
        if (collection != msg.sender && !IPermissions(collection).hasPermission(Operations.ADMIN, msg.sender)) {
            revert SetUpUnauthorized(collection, msg.sender);
        }
        _;
    }
}

