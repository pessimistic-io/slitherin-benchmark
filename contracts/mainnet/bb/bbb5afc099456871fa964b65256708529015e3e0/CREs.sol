
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Casual Random Editions
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
//                                                                              //
//      sSSs. d ss.  d sss     sss.      d ss.  Ss   sS      d ss    d ss.      //
//     S      S    b S       d           S    b   S S        S   ~o  S    b     //
//    S       S    P S       Y           S    P    S         S     b S    P     //
//    S       S sS'  S sSSs    ss.       S sSS'    S         S     S S sSS'     //
//    S       S   S  S            b      S    b    S         S     P S    b     //
//     S      S    S S            P      S    P    S         S    S  S    P     //
//      "sss' P    P P sSSss ` ss'       P `SS     P         P ss"   P `SS      //
//                                                                              //
//                                                                              //
//                                                                              //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////


contract CREs is ERC1155Creator {
    constructor() ERC1155Creator("Casual Random Editions", "CREs") {}
}

