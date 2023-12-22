// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OFTV2.sol";

/// @title SurvToken OFTV2
contract SurvOFT is OFTV2 {
    constructor(address _layerZeroEndpoint, uint8 _sharedDecimals)
        OFTV2("SurvToken", "SURV", _sharedDecimals, _layerZeroEndpoint)
    {}    
}

