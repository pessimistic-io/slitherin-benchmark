//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BugzState.sol";

abstract contract BugzContracts is Initializable, BugzState {

    function __BugzContracts_init() internal initializer {
        BugzState.__BugzState_init();
    }
}
