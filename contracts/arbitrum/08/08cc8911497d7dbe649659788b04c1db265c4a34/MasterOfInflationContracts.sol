//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./MasterOfInflationState.sol";

abstract contract MasterOfInflationContracts is Initializable, MasterOfInflationState {

    function __MasterOfInflationContracts_init() internal initializer {
        MasterOfInflationState.__MasterOfInflationState_init();
    }
}
