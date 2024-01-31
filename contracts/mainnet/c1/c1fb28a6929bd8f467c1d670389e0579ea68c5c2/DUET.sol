// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Duet
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////
//                                //
//                                //
//      _____             _       //
//     |  __ \           | |      //
//     | |  | |_   _  ___| |_     //
//     | |  | | | | |/ _ \ __|    //
//     | |__| | |_| |  __/ |_     //
//     |_____/ \__,_|\___|\__|    //
//                                //
//                                //
//                                //
//                                //
////////////////////////////////////


contract DUET is ERC721Creator {
    constructor() ERC721Creator("Duet", "DUET") {}
}

