// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AccessControlEnumerable.sol";

contract AccessRegistry is AccessControlEnumerable {
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
}

