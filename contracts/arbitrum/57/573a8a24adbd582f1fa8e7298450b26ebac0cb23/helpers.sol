//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import { TokenInterface } from "./interfaces.sol";
import { DSMath } from "./math.sol";
import { Basic } from "./basic.sol";


abstract contract Helpers is DSMath, Basic {
    /**
     * @dev 1Inch Router v5 Address
     */
    address internal constant oneInchAddr = 0x1111111254EEB25477B68fb85Ed929f73A960582;
}
