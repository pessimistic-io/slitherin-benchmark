// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesHedgingV3Strategy} from "./JonesHedgingV3Strategy.sol";

contract JonesGOHMHedgingV3Strategy is JonesHedgingV3Strategy {
    constructor() JonesHedgingV3Strategy(
        "JonesGOHMHedgingV3Strategy",
        0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1, // gOHM
        0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774, // Jones Multisig
        new address[](0)
    ) {
        address[] memory tokensToWhitelist = new address[](7);

        tokensToWhitelist[0] = 0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55; // DPX
        tokensToWhitelist[1] = 0x32Eb7902D4134bf98A28b963D26de779AF92A212; // rDPX
        tokensToWhitelist[2] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // wETH
        tokensToWhitelist[3] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // wBTC
        tokensToWhitelist[4] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // USDC
        tokensToWhitelist[5] = 0x7f90122BF0700F9E7e1F688fe926940E8839F353; // 2CRV
        tokensToWhitelist[6] = 0x8D9bA570D6cb60C7e3e0F31343Efe75AB8E65FB1; // gOHM

        _whitelistTokens(tokensToWhitelist);
    }
}


