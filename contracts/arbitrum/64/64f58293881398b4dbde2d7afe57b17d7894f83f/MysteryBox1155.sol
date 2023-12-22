// SPDX-License-Identifier: MIT
// Mateline Contracts (MysteryBox1155.sol)

pragma solidity ^0.8.0;

import "./Extendable1155.sol";

// 1155 id : combine with randomType(uint32) << 32 | mysteryType(uint32)
contract MysteryBox1155 is Extendable1155 {

    constructor(string memory uri) Extendable1155("MetaLine MysteryBox Semi-fungible Token", "MLMB", uri) {
        mint(_msgSender(), 0, 1, new bytes(0)); // mint first token to notify event scan
    }
}
