// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// from https://bscscan.com/address/0xA39Af17CE4a8eb807E076805Da1e2B8EA7D0755b#code
library Math {
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }
}

