
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: ASEPONDE
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////////
//                                           //
//                                           //
//                                           //
//     _____                       _         //
//    |  _  |___ ___ ___ ___ ___ _| |___     //
//    |     |_ -| -_| . | . |   | . | -_|    //
//    |__|__|___|___|  _|___|_|_|___|___|    //
//                  |_|                      //
//                                           //
//                                           //
///////////////////////////////////////////////


contract AO is ERC721Creator {
    constructor() ERC721Creator("ASEPONDE", "AO") {}
}

