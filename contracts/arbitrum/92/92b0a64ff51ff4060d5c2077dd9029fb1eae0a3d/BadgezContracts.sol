//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./BadgezState.sol";

abstract contract BadgezContracts is Initializable, BadgezState {

    function __BadgezContracts_init() internal initializer {
        BadgezState.__BadgezState_init();
    }
}
