
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: MINIMAL IS ME
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////
//                                       //
//                                       //
//                                       //
//    █░█ ▄▀█ █▀▄▀█ █░░ █▀█ █▀▀ █ █▀▀    //
//    █▀█ █▀█ █░▀░█ █▄▄ █▄█ █▄█ █ █▄▄    //
//                                       //
//                                       //
///////////////////////////////////////////


contract MNML is ERC721Creator {
    constructor() ERC721Creator("MINIMAL IS ME", "MNML") {}
}

