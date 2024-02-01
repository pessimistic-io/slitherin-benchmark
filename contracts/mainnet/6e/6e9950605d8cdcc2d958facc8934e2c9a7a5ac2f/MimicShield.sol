
// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { CoreShield } from "./CoreShield.sol";
import { Combo721Base } from "./Combo721Base.sol";


contract MimicShield is CoreShield {
    constructor()
        Combo721Base("Mimic Shield", "MIMSOE")
        {}
}





