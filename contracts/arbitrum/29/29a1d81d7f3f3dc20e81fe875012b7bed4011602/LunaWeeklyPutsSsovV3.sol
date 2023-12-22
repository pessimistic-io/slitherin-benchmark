//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title LUNA Weekly Puts SSOV V3 contract
contract LunaWeeklyPutsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "LUNA WEEKLY PUTS SSOV V3",
            "LUNA-WEEKLY-PUTS-SSOV-V3",
            "LUNA",
            0x7f90122BF0700F9E7e1F688fe926940E8839F353,
            true
        )
    {}
}

