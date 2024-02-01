
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: 0xArtSpread / Bidders Editions
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////////////////
//                                                           //
//                                                           //
//    ,--.         ,.       .  .---.                   .     //
//    |  | . ,    / |   ,-. |- \___  ,-. ,-. ,-. ,-. ,-|     //
//    |  |  X    /~~|-. |   |      \ | | |   |-' ,-| | |     //
//    `--' ' ` ,'   `-' '   `' `---' |-' '   `-' `-^ `-'     //
//                                   |                       //
//                                          By 0xFineArt     //
//                                                           //
//                                                           //
///////////////////////////////////////////////////////////////


contract OxASBE is ERC1155Creator {
    constructor() ERC1155Creator("0xArtSpread / Bidders Editions", "OxASBE") {}
}

