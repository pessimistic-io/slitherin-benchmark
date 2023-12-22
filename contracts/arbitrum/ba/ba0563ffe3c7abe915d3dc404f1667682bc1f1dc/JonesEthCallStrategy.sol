// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesSSOVCallV3Strategy} from "./JonesSSOVCallV3Strategy.sol";

contract JonesEthCallStrategy is JonesSSOVCallV3Strategy {
    constructor()
        JonesSSOVCallV3Strategy(
            "JonesEthCallStrategy",
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH
            0xC59836FEC63Cfb2E48b0aa00515056436D74Dc03, // ETH Monthly SSOV-C
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774  // Multisig address
        )
    {}
}

