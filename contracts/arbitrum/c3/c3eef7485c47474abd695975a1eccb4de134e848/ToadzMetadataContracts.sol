//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ToadzMetadataState.sol";

abstract contract ToadzMetadataContracts is Initializable, ToadzMetadataState {

    function __ToadzMetadataContracts_init() internal initializer {
        ToadzMetadataState.__ToadzMetadataState_init();
    }
}
