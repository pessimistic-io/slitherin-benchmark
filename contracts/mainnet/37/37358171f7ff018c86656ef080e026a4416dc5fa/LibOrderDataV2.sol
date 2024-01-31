// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./LibPart.sol";

library LibOrderDataV2 {
    bytes4 public constant V2 = bytes4(keccak256("V2"));

    struct DataV2 {
        LibPart.Part[] payouts;
        LibPart.Part[] originFees;
        bool isMakeFill;
    }
}

