
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: FIRE & FLOW
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////
//                   //
//                   //
//    FIRE & FLOW    //
//                   //
//                   //
///////////////////////


contract FF is ERC721Creator {
    constructor() ERC721Creator("FIRE & FLOW", "FF") {}
}

