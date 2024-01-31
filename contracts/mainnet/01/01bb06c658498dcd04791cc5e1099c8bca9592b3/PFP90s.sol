
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: 0x90sAesthetic x PFP
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////
//                                        //
//                                        //
//                                        //
//    !        _               _ __ _     //
//    !  0x90s//\esthetic  x  ||)|-||)    //
//    !                       L|   L|     //
//                                        //
//                                        //
//                                        //
////////////////////////////////////////////


contract PFP90s is ERC721Creator {
    constructor() ERC721Creator("0x90sAesthetic x PFP", "PFP90s") {}
}

