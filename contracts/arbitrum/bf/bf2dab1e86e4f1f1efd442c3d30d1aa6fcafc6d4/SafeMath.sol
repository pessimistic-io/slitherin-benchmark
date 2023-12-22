// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.6;

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMathUniswap {
    function add(uint x, uint y) internal pure returns (uint z) {
        return x + y;
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        return x - y;
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        return x * y;
    }
}

