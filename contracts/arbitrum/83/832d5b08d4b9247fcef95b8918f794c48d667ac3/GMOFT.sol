// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./OFT.sol";

contract GMOFT is OFT {
    constructor(address _lzEndpoint) OFT("Good Morning", "GM", _lzEndpoint){}
}

