//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ItemzState.sol";

abstract contract ItemzContracts is Initializable, ItemzState {

    function __ItemzContracts_init() internal initializer {
        ItemzState.__ItemzState_init();
    }
}
