//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ToadHousezMetadataState.sol";

abstract contract ToadHousezMetadataContracts is ToadHousezMetadataState {

    function __ToadHousezMetadataContracts_init() internal initializer {
        ToadHousezMetadataState.__ToadHousezMetadataState_init();
    }
}
