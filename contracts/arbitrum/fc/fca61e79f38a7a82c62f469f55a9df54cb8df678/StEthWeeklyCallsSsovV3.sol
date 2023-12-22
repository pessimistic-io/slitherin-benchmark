//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title stETH Weekly Calls SSOV V3 contract
contract StEthWeeklyCallsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "stETH WEEKLY CALLS SSOV V3",
            "stETH-WEEKLY-CALLS-SSOV-V3",
            "stETH",
            0x5979D7b546E38E414F7E9822514be443A4800529,
            false
        )
    {}
}

