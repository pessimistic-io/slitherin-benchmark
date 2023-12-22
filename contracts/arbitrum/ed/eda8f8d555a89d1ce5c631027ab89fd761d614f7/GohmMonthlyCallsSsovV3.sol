//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title gOHM Monthly Calls SSOV V3 contract
contract GohmMonthlyCallsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "gOHM MONTHLY CALLS SSOV V3",
            "gOHM-MONTHLY-CALLS-SSOV-V3",
            "gOHM",
            0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1,
            false
        )
    {}
}

