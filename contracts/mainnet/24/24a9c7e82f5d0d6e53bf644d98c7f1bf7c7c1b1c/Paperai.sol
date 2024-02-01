
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Paper&ai
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////////
//                                           //
//                                           //
//     ▄▄▄· ▄▄▄·  ▄▄▄·▄▄▄ .▄▄▄   ▄▄▄· ▪      //
//    ▐█ ▄█▐█ ▀█ ▐█ ▄█▀▄.▀·▀▄ █·▐█ ▀█ ██     //
//     ██▀·▄█▀▀█  ██▀·▐▀▀▪▄▐▀▀▄ ▄█▀▀█ ▐█·    //
//    ▐█▪·•▐█ ▪▐▌▐█▪·•▐█▄▄▌▐█•█▌▐█ ▪▐▌▐█▌    //
//    .▀    ▀  ▀ .▀    ▀▀▀ .▀  ▀ ▀  ▀ ▀▀▀    //
//                                           //
//                                           //
///////////////////////////////////////////////


contract Paperai is ERC721Creator {
    constructor() ERC721Creator("Paper&ai", "Paperai") {}
}

