// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {JonesLPBullStrategy, I1inchAggregationRouterV4, ISsovV3, IERC20} from "./JonesLPBullStrategy.sol";

contract JonesDpxEthBullStrategy is JonesLPBullStrategy {
    constructor()
        JonesLPBullStrategy(
            "JonesDpxEthBullStrategy",
            I1inchAggregationRouterV4(
                payable(0x1111111254fb6c44bAC0beD2854e76F90643097d)
            ), // 1Inch router
            ISsovV3(0x9Cc9BeffE64868CB4B97890A19219449890E6eA0), // Primary weekly Ssov ETH
            ISsovV3(0x10FD85ec522C245a63239b9FC64434F58520bd1f), // Primary weekly Ssov DPX
            IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1), // WETH
            IERC20(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55), // DPX
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774, // Governor: Jones Multisig
            0xDD0556DDCFE7CdaB3540E7F09cB366f498d90774, // Strats: Jones Multisig
            0x575A84A7E58Af8686126Da44DDBEe064644915Ad // Bot
        )
    {}
}

