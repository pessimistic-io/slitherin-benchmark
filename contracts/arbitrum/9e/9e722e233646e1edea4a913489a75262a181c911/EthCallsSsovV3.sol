//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {SsovV3} from "./SsovV3.sol";

/// @title ETH Calls SSOV V3 contract (Flexible time period vault)
contract EthCallsSsovV3 is SsovV3 {
    constructor()
        SsovV3(
            "ETH CALLS SSOV V3",
            "ETH-CALLS-SSOV-V3",
            "ETH",
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            false
        )
    {}
}

