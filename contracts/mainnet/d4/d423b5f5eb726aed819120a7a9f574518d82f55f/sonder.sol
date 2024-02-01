
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: sonder
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////
//            //
//            //
//    love    //
//            //
//            //
////////////////


contract sonder is ERC721Creator {
    constructor() ERC721Creator("sonder", "sonder") {}
}

