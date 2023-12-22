// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesSSOVPutV3Strategy} from "./JonesSSOVPutV3Strategy.sol";

contract JonesRdpxPutStrategy is JonesSSOVPutV3Strategy {
    constructor()
        JonesSSOVPutV3Strategy(
            "JonesRdpxPutStrategy",
            0x32Eb7902D4134bf98A28b963D26de779AF92A212, // rDPX
            0xb4ec6B4eC9e42A42B0b8cdD3D6df8867546Cf11d, // rDPX Weekly SSOV-P
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774 // Multisig address
        )
    {}
}

