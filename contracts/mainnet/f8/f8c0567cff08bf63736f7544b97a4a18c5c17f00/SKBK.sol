
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Skybrook
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////
//                //
//                //
//    Skybrook    //
//                //
//                //
////////////////////


contract SKBK is ERC721Creator {
    constructor() ERC721Creator("Skybrook", "SKBK") {}
}

