// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ProxyOFTV2.sol";

contract ArkenTokenProxyOFT is ProxyOFTV2 {
    constructor(address _token, uint8 _sharedDecimals, address _layerZeroEndpoint) ProxyOFTV2(_token, _sharedDecimals, _layerZeroEndpoint){}
}

