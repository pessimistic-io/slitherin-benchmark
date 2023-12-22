// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesSSOVCallV3Strategy} from "./JonesSSOVCallV3Strategy.sol";

contract JonesGohmCallStrategy is JonesSSOVCallV3Strategy {
    constructor()
        JonesSSOVCallV3Strategy(
            "JonesGohmCallStrategy",
            0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1, // gOHM
            0x546cd36F761f1D984eEE1Dbe67cC4F86E75cAF0C, // gOHM Weekly SSOV-C
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774 // Multisig address
        )
    {}
}

