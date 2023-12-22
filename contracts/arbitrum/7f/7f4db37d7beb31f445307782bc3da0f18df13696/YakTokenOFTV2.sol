// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OFTV2.sol";

contract YakTokenOFTV2 is OFTV2 {
    constructor(address _layerZeroEndpoint, uint8 _sharedDecimals) OFTV2("Yak Token", "YAK", _sharedDecimals, _layerZeroEndpoint) {}
}

