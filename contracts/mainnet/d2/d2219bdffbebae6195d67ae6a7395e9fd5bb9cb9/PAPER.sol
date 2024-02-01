
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: PaperHand
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////
//                                   //
//                                   //
//    ___________ __        __       //
//    \_   _____/|__|____ _/  |_     //
//     |    __)  |  \__  \\   __\    //
//     |     \   |  |/ __ \|  |      //
//     \___  /   |__(____  /__|      //
//         \/            \/          //
//                                   //
//                                   //
///////////////////////////////////////


contract PAPER is ERC721Creator {
    constructor() ERC721Creator("PaperHand", "PAPER") {}
}

