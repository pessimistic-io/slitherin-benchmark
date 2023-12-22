// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./OFTV2.sol";

contract LBRL2 is OFTV2 {

    constructor(uint8 _sharedDecimals, address _lzEndpoint) OFTV2("Lybra", "LBR", _sharedDecimals, _lzEndpoint) {
    }
}

