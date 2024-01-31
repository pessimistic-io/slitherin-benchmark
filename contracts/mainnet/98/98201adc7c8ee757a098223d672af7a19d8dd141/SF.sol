
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: SPACE FACE
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////////////
//                                                 //
//                                                 //
//      ___ ___  _   ___ ___   ___ _   ___ ___     //
//     / __| _ \/_\ / __| __| | __/_\ / __| __|    //
//     \__ \  _/ _ \ (__| _|  | _/ _ \ (__| _|     //
//     |___/_|/_/ \_\___|___| |_/_/ \_\___|___|    //
//                                                 //
//                                                 //
//                                                 //
/////////////////////////////////////////////////////


contract SF is ERC721Creator {
    constructor() ERC721Creator("SPACE FACE", "SF") {}
}

