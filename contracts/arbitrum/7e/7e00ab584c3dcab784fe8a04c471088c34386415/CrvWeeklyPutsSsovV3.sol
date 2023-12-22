//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title CRV Weekly Puts SSOV V3 contract
contract CrvWeeklyPutsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "CRV WEEKLY PUTS SSOV V3",
            "CRV-WEEKLY-PUTS-SSOV-V3",
            "CRV",
            0x7f90122BF0700F9E7e1F688fe926940E8839F353,
            true
        )
    {}
}

