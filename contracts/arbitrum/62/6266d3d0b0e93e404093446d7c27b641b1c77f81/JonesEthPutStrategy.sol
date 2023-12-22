// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesSSOVPutV3Strategy} from "./JonesSSOVPutV3Strategy.sol";

contract JonesEthPutStrategy is JonesSSOVPutV3Strategy {
    constructor()
        JonesSSOVPutV3Strategy(
            "JonesEthPutStrategy",
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH
            0x32449DF9c617C59f576dfC461D03f261F617aD5a, // ETH Weekly SSOV-P
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774 // Multisig address
        )
    {}
}

