// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./OFTWithFee.sol";

contract Metis is OFTWithFee {
    constructor(address _lzEndpoint) OFTWithFee("Metis", "METIS", 18, _lzEndpoint) {}
}
