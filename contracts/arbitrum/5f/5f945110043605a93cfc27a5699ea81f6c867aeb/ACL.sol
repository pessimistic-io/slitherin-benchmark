// SPDX-License-Identifier: GNU GPLv3
pragma solidity >=0.8.10;

import {AccessControl} from "./AccessControl.sol";

abstract contract ACL is AccessControl {
    error NotEOA(address origin, address sender);
    error NotAdmin();

    modifier onlyEOA() {
        if (tx.origin != msg.sender) {
            revert NotEOA(tx.origin, msg.sender);
        }
        _;
    }

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender())) {
            revert NotAdmin();
        }
        _;
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}

