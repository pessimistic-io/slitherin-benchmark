
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: WGRT_
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////////////////////////
//                                                                   //
//                                                                   //
//    ´´´´´´´´´´´´´´´´´´´´´´HHHHHHHHHHHHHHH´´´´´´´´´´´´´´´´´´´´´´    //
//    ´´´´´´´´´´´´´´´´´HHHHHH´´´´´´´´´´´´´HHHHHH´´´´´´´´´´´´´´´´´    //
//    ´´´´´´´´´´´´´´HHHH´´´´´´´´´´´´´´´´´´´´´´´HHHH´´´´´´´´´´´´´´    //
//    ´´´´´´´´´´´´´HHH´´´´´´´´´´´´´´´´´´´´´´´´´´´´HHH´´´´´´´´´´´´    //
//    ´´´´´´´´´´´´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´´´´´´´´´´´    //
//    ´´´´´´´´´´´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´´´´´´´´´´    //
//    ´´´´´´´´´´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´´´´´´´´´´    //
//    ´´´´´´´´´´HH´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´HH´´´´´´´´´´    //
//    ´´´´´´´´´´HH´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´HH´´´´´´´´´´    //
//    ´´´´´´´´´´HH´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´HH´´´´´´´´´´    //
//    ´´´´´´´´´´HH´´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´HH´´´´´´´´´´    //
//    ´´´´´´´´´´HH´´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´´HH´´´´´´´´´´    //
//    ´´´´´´´´´´´HH´HH´´´HHHHHHHH´´´´´HHHHHHHH´´´HH´HH´´´´´´´´´´´    //
//    ´´´´´´´´´´´´HHHH HHHHHHHHHH´´´´´HHHHHHHHHH´HHHH´´´´´´´´´´´     //
//    ´´´´´´´´´´´´´HHH´HHHHHHHHHH´´´´´HHHHHHHHHH´HHH´´´´´´´´´´´´´    //
//    ´´´HHHH´´´´´´HH´´HHHHHHHHH´´´´´´´HHHHHHHHH´´HH´´´´´´HHHH´´´    //
//    ´´HHHHHH´´´´´HH´´´HHHHHHH´´´HHH´´´HHHHHHH´´´HH´´´´´HHHHHH´´    //
//    ´´HH´´´HH´´´´HH´´´´´HHH´´´´HHHHH´´´´HHH´´´´´HH´´´´HH´´´HH´´    //
//    ´ HHH´´´´ HHHH´´HH´´´´´´´´HHHHHHH´´´´´´´´HH´´HHHH´´´´ HHH´     //
//    HH´´´´´´´´HHHHHHHHH´´´´´´HHHHHHH´´´´´´HHHHHHHHH´´´´´´´´HH      //
//    HHHHHHHH ´´´´´HHHHHHHH´´´´HHHHHHH´´´´HHHHHHHH´´´´´´HHHHHHHH    //
//    ´HHHH´HHHHHH´´´´´HH HHH´´´´´´´´´´´´´´HHH´HH´´´´´HHHHHH´HHH´    //
//    ´´´´´´´´´´HHHHHH´´HHH´HH´´´´´´´´´´´HH´´HHH´´HHHHHH´´´´´´´´     //
//    ´´´´´´´´´´´´´´HHHHHH´HH´HHHHHHHHHHH´HH´HHHHHH´´´´´´´´´´´´´´    //
//    ´´´´´´´´´´´´´´´´´´HH´HH´H´H´H´H´H´H´HH´HH´´´´´´´´´´´´´´´´´     //
//    ´´´´´´´´´´´´´´´´HHHH´´H´H´H´H´H´H´H´H´´HHHH´´´´´´´´´´´´´´      //
//    ´´´´´´´´´´´´HHHHH´HH´´´HHHHHHHHHHHHH´´´HH´HHHHH´´´´´´´´´´´´    //
//    ´´´´HHHHHHHHH ´´´´´HH´´´´´´´´´´´´´´´´´HH´´´´´´HHHHHHHHH´´´´    //
//    ´´´HH´´´´´´´´´´´HHHHHHH´´´´´´´´´´´´´HHHHHHH´´´´´´´´´´ HH´´´    //
//    ´´´´HHH´´´´´HHHHH´´´´´HHHHHHHHHHHHHHH´´´´´HHHHH´´´´´HHH´´´´    //
//    ´´´´´´HH´´´HHH´´´´´´´´´´´HHHHHHHHH´´´´´´´´´´´HHH´´´HH´´´´´´    //
//    ´´´´´´HH´´HH´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´HH´´HH´´´´´´    //
//    ´´´´´´´HHHHH´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´´HHHH´´´´´´´    //
//                                                                   //
//                                                                   //
///////////////////////////////////////////////////////////////////////


contract WGRT is ERC1155Creator {
    constructor() ERC1155Creator("WGRT_", "WGRT") {}
}

