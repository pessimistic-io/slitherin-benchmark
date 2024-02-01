// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Real Pixel
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////
//                                         //
//                                         //
//                                         //
//    █▀█ █▀▀ ▄▀█ █░░ █▀█ █ ▀▄▀ █▀▀ █░░    //
//    █▀▄ ██▄ █▀█ █▄▄ █▀▀ █ █░█ ██▄ █▄▄    //
//                                         //
//                                         //
/////////////////////////////////////////////


contract RealPixel is ERC721Creator {
    constructor() ERC721Creator("Real Pixel", "RealPixel") {}
}

