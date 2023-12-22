// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {OFTV2} from "./OFTV2.sol";

contract Tenet is OFTV2 {
    constructor(address _lzEndpoint) OFTV2("TENET", "TENET", 6, _lzEndpoint) {}
}
