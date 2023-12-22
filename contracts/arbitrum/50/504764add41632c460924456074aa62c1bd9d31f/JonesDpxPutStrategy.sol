// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesSSOVPutV3Strategy} from "./JonesSSOVPutV3Strategy.sol";

contract JonesDpxPutStrategy is JonesSSOVPutV3Strategy {
    constructor()
        JonesSSOVPutV3Strategy(
            "JonesDpxPutStrategy",
            0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55, // DPX
            0xf71b2B6fE3c1d94863e751d6B455f750E714163C, // DPX Weekly SSOV-P
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774 // Multisig address
        )
    {}
}

