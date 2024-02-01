
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: MorSella's Art Classics
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////
//            //
//            //
//    MSAc    //
//            //
//            //
//            //
//            //
////////////////


contract MSAc is ERC721Creator {
    constructor() ERC721Creator("MorSella's Art Classics", "MSAc") {}
}

