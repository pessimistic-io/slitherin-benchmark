
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Melts in the mouth...
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                           //
//                                                                                                                           //
//                                                                                                                           //
//                                                                                                                           //
//    EEEEEEEEEEEEEEEEEEEEEERRRRRRRRRRRRRRRRR   RRRRRRRRRRRRRRRRR        OOOOOOOOO     RRRRRRRRRRRRRRRRR                     //
//    E::::::::::::::::::::ER::::::::::::::::R  R::::::::::::::::R     OO:::::::::OO   R::::::::::::::::R                    //
//    E::::::::::::::::::::ER::::::RRRRRR:::::R R::::::RRRRRR:::::R  OO:::::::::::::OO R::::::RRRRRR:::::R                   //
//    EE::::::EEEEEEEEE::::ERR:::::R     R:::::RRR:::::R     R:::::RO:::::::OOO:::::::ORR:::::R     R:::::R                  //
//      E:::::E       EEEEEE  R::::R     R:::::R  R::::R     R:::::RO::::::O   O::::::O  R::::R     R:::::R                  //
//      E:::::E               R::::R     R:::::R  R::::R     R:::::RO:::::O     O:::::O  R::::R     R:::::R                  //
//      E::::::EEEEEEEEEE     R::::RRRRRR:::::R   R::::RRRRRR:::::R O:::::O     O:::::O  R::::RRRRRR:::::R                   //
//      E:::::::::::::::E     R:::::::::::::RR    R:::::::::::::RR  O:::::O     O:::::O  R:::::::::::::RR                    //
//      E:::::::::::::::E     R::::RRRRRR:::::R   R::::RRRRRR:::::R O:::::O     O:::::O  R::::RRRRRR:::::R                   //
//      E::::::EEEEEEEEEE     R::::R     R:::::R  R::::R     R:::::RO:::::O     O:::::O  R::::R     R:::::R                  //
//      E:::::E               R::::R     R:::::R  R::::R     R:::::RO:::::O     O:::::O  R::::R     R:::::R                  //
//      E:::::E       EEEEEE  R::::R     R:::::R  R::::R     R:::::RO::::::O   O::::::O  R::::R     R:::::R                  //
//    EE::::::EEEEEEEE:::::ERR:::::R     R:::::RRR:::::R     R:::::RO:::::::OOO:::::::ORR:::::R     R:::::R                  //
//    E::::::::::::::::::::ER::::::R     R:::::RR::::::R     R:::::R OO:::::::::::::OO R::::::R     R:::::R                  //
//    E::::::::::::::::::::ER::::::R     R:::::RR::::::R     R:::::R   OO:::::::::OO   R::::::R     R:::::R                  //
//    EEEEEEEEEEEEEEEEEEEEEERRRRRRRR     RRRRRRRRRRRRRRR     RRRRRRR     OOOOOOOOO     RRRRRRRR     RRRRRRR                  //
//                                                                                                                           //
//    | TIM_GRIB...ANALOG/DIGITAL CREATOR |                                                                                  //
//                                                                                                                           //
//                                                                                                                           //
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract MITM is ERC1155Creator {
    constructor() ERC1155Creator("Melts in the mouth...", "MITM") {}
}

