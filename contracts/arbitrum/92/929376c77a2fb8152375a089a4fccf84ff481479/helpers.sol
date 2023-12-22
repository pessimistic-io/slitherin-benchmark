pragma solidity ^0.7.0;

import { TokenInterface } from "./interfaces.sol";
import { DSMath } from "./math.sol";
import { Basic } from "./basic.sol";


abstract contract Helpers is DSMath, Basic {
    /**
     * @dev 1Inch Address
     */
address internal constant oneInchAddr = 0x1111111254fb6c44bAC0beD2854e76F90643097d;
}
