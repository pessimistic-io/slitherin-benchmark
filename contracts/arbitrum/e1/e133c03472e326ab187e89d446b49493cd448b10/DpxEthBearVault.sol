// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BearLPVault} from "./BearLPVault.sol";

contract DpxEthBearVault is BearLPVault {
    constructor()
        BearLPVault(
            0x0C1Cf6883efA1B496B01f654E247B9b419873054, // Dpx-Eth LP Token
            address(0x1e492003667c3834f117682485c91603aC5291eC), // Replace with storage address
            "JonesDpxEthBearVault",
            1e11, // Risk percentage (1e12 = 100%)
            2e10, // Fee percentage (1e12 = 100%)
            0xcCdb22C29f849C2c34380d64217cB8636DEA6b24, // Fee receiver
            payable(0x1111111254fb6c44bAC0beD2854e76F90643097d), // 1Inch router
            10e18, // Cap
            0x1f80C96ca521d7247a818A09b0b15C38E3e58a28 // Dpx-Eth Farm
        )
    {}
}

