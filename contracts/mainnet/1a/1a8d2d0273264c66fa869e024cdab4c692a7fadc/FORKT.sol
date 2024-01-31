
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: FORKT by HUMAN GEOMETRY
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////////////
//                                                  //
//                                                  //
//                                                  //
//    ███████  ██████  ██████  ██   ██ ████████     //
//    ██      ██    ██ ██   ██ ██  ██     ██        //
//    █████   ██    ██ ██████  █████      ██        //
//    ██      ██    ██ ██   ██ ██  ██     ██        //
//    ██       ██████  ██   ██ ██   ██    ██        //
//                                                  //
//                                                  //
//                                                  //
//                                                  //
//                                                  //
//////////////////////////////////////////////////////


contract FORKT is ERC1155Creator {
    constructor() ERC1155Creator("FORKT by HUMAN GEOMETRY", "FORKT") {}
}

