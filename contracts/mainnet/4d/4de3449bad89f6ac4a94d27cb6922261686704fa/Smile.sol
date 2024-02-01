
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Smile
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////
//                                      //
//                                      //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXsmileXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//    XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX    //
//                                      //
//                                      //
//////////////////////////////////////////


contract Smile is ERC1155Creator {
    constructor() ERC1155Creator("Smile", "Smile") {}
}

