//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title rDPX Weekly Calls SSOV V3 contract
contract RdpxWeeklyCallsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "rDPX WEEKLY CALLS SSOV V3",
            "rDPX-WEEKLY-CALLS-SSOV-V3",
            "rDPX",
            0x32Eb7902D4134bf98A28b963D26de779AF92A212,
            false
        )
    {}
}

