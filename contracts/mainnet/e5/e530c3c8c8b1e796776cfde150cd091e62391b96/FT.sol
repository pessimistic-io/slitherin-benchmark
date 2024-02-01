
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Fisherman's Tale
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////
//                         //
//                         //
//                         //
//      ______ _______     //
//     |  ____|__   __|    //
//     | |__     | |       //
//     |  __|    | |       //
//     | |       | |       //
//     |_|       |_|       //
//                         //
//                         //
//                         //
//                         //
//                         //
/////////////////////////////


contract FT is ERC721Creator {
    constructor() ERC721Creator("Fisherman's Tale", "FT") {}
}

