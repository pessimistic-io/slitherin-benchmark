//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title CVX Weekly Puts SSOV V3 contract
contract CvxWeeklyPutsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "CVX WEEKLY PUTS SSOV V3",
            "CVX-WEEKLY-PUTS-SSOV-V3",
            "CVX",
            0x7f90122BF0700F9E7e1F688fe926940E8839F353,
            true
        )
    {}
}

