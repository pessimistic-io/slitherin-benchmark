// SPDX-License-Identifier: GPL-3.0-or-later

// A modified version of V3Path library
// Unused methods and constants were removed

pragma solidity 0.8.18;

import {BytesLib} from "./BytesLib.sol";

/// @title Functions for manipulating path data for multihop swaps
library V3Path {
    using BytesLib for bytes;

    function decodeFirstToken(bytes memory path) internal pure returns (address tokenA) {
        tokenA = path.toAddress(0, path.length);
    }
}

