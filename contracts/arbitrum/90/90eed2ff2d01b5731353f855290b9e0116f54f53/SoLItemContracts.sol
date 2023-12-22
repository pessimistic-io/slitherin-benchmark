//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./SoLItemState.sol";

abstract contract SoLItemContracts is Initializable, SoLItemState {

    function __SoLItemContracts_init() internal initializer {
        SoLItemState.__SoLItemState_init();
    }
}
