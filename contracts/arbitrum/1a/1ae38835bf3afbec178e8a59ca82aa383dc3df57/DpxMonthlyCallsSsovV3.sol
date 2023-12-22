//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title DPX Monthly Calls SSOV V3 contract
contract DpxMonthlyCallsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "DPX MONTHLY CALLS SSOV V3 2",
            "DPX-MONTHLY-CALLS-SSOV-V3-2",
            "DPX",
            0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55,
            false
        )
    {}
}

