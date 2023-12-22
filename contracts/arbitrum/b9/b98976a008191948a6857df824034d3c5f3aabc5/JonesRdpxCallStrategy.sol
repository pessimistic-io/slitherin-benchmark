// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesSSOVCallV3Strategy} from "./JonesSSOVCallV3Strategy.sol";

contract JonesRdpxCallStrategy is JonesSSOVCallV3Strategy {
    constructor()
        JonesSSOVCallV3Strategy(
            "JonesRdpxCallStrategy",
            0x32Eb7902D4134bf98A28b963D26de779AF92A212, // rDPX
            0xd74c61ca8917Be73377D74A007E6f002c25Efb4e, // rDPX Monthly SSOV-C
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774 // Multisig address
        )
    {}
}

