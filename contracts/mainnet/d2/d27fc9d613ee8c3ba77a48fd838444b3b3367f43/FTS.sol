
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: FAKE THE SHAPE
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////
//                    //
//                    //
//    FAKETHESHAPE    //
//                    //
//                    //
////////////////////////


contract FTS is ERC721Creator {
    constructor() ERC721Creator("FAKE THE SHAPE", "FTS") {}
}

