// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Artworks by Vrenarn
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////
//                           //
//                           //
//    Artworks by Vrenarn    //
//                           //
//                           //
///////////////////////////////


contract Artwork is ERC721Creator {
    constructor() ERC721Creator("Artworks by Vrenarn", "Artwork") {}
}

