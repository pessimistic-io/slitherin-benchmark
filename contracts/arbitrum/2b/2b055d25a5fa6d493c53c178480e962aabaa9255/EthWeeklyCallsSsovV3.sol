//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title ETH SSOV V3 contract
contract EthWeeklyCallsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "ETH WEEKLY CALLS SSOV V3 2",
            "ETH-WEEKLY-CALLS-SSOV-V3-2",
            "ETH",
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            false
        )
    {}
}

