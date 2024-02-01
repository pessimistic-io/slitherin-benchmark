
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Moonlight
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////
//                 //
//                 //
//    Moonlight    //
//                 //
//                 //
/////////////////////


contract MOON is ERC721Creator {
    constructor() ERC721Creator("Moonlight", "MOON") {}
}

