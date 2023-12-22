// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesSSOVCallV3Strategy} from "./JonesSSOVCallV3Strategy.sol";

contract JonesDpxCallStrategy is JonesSSOVCallV3Strategy {
    constructor()
        JonesSSOVCallV3Strategy(
            "JonesDpxCallStrategy",
            0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55, // DPX
            0x05E7ACeD3b7727f9129E6d302B488cd8a1e0C817, // DPX Monthly SSOV-C
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774 // Multisig address
        )
    {}
}

