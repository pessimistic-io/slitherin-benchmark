
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: ONE
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////
//                           //
//                           //
//                           //
//      ___  _   _ _____     //
//     / _ \| | / |____ |    //
//    | | | | |/  | |_  |    //
//    | |_| |  /| |___| |    //
//     \___/|_/ |_|_____|    //
//                           //
//                           //
//                           //
//                           //
///////////////////////////////


contract ONE is ERC721Creator {
    constructor() ERC721Creator("ONE", "ONE") {}
}

