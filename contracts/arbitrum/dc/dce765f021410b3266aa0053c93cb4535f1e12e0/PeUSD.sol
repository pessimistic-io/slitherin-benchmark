// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./OFTV2.sol";

contract PeUSD is OFTV2 {

    constructor(uint8 _sharedDecimals, address _lzEndpoint) OFTV2("peg-eUSD", "peUSD", _sharedDecimals, _lzEndpoint) {
    }
}

