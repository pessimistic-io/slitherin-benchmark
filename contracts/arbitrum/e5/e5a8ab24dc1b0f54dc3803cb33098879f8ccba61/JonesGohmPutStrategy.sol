// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesSSOVPutV3Strategy} from "./JonesSSOVPutV3Strategy.sol";

contract JonesGohmPutStrategy is JonesSSOVPutV3Strategy {
    constructor()
        JonesSSOVPutV3Strategy(
            "JonesGohmPutStrategy",
            0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1, // gOHM
            0x4269AF9076586230bF5fa3655144a5fe9CB877Fd, // gOHM Weekly SSOV-P
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774 // Multisig address
        )
    {}
}

