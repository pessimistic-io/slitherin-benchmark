
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: H01 Collabs
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////////////
//                                                                //
//                                                                //
//       ____  ___) __    _      )   ___                          //
//      (, /   /  /   ) / /     (__/_____)    /) /)     /)        //
//        /---/  /   /   /        /       ___// // _   (/_ _      //
//     ) /   (__(__ /   /        /       (_)(/_(/_(_(_/_) /_)_    //
//    (_/              /        (______)                          //
//                                                                //
//                                                                //
////////////////////////////////////////////////////////////////////


contract H01C is ERC721Creator {
    constructor() ERC721Creator("H01 Collabs", "H01C") {}
}

