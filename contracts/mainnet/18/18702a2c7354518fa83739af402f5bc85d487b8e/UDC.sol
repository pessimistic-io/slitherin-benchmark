
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Undead Social Club
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////
//                   //
//                   //
//    EaZy-ApeZ #    //
//                   //
//                   //
///////////////////////


contract UDC is ERC721Creator {
    constructor() ERC721Creator("Undead Social Club", "UDC") {}
}

