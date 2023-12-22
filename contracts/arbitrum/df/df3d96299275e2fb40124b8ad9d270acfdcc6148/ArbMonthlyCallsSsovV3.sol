//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title ARB Monthly Calls SSOV V3 contract
contract ArbMonthlyCallsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "ARB MONTHLY CALLS SSOV V3",
            "ARB-MONTHLY-CALLS-SSOV-V3",
            "ARB",
            0x912CE59144191C1204E64559FE8253a0e49E6548,
            false
        )
    {}
}

