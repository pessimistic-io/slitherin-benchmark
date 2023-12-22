//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title gOHM Weekly Puts SSOV V3 contract
contract GohmWeeklyPutsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "gOHM WEEKLY PUTS SSOV V3 2",
            "gOHM-WEEKLY-PUTS-SSOV-V3-2",
            "gOHM",
            0x7f90122BF0700F9E7e1F688fe926940E8839F353,
            true
        )
    {}
}

