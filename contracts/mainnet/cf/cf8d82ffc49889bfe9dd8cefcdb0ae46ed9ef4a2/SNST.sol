
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Sunset In December
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////
//              //
//              //
//    SNST-1    //
//              //
//              //
//////////////////


contract SNST is ERC721Creator {
    constructor() ERC721Creator("Sunset In December", "SNST") {}
}

