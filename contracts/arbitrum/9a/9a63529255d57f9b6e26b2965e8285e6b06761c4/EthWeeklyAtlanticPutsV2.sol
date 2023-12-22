//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Contracts
import {AtlanticPutsPool} from "./AtlanticPutsPool.sol";

/// @title BTC Weekly Puts SSOV V3 contract
contract EthWeeklyAtlanticPutsV2 is AtlanticPutsPool {
    constructor()
        AtlanticPutsPool(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8)
    {}
}

