
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: The Memes by 6529
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////
//                                                        //
//                                                        //
//    First tweet, first gm                               //
//                                                        //
//    [what a noob, I can't believe he capitalized it]    //
//                                                        //
//    Meme: 4                                             //
//    Season: 1                                           //
//    Card: 1                                             //
//                                                        //
//                                                        //
////////////////////////////////////////////////////////////


contract GM is ERC721Creator {
    constructor() ERC721Creator("The Memes by 6529", "GM") {}
}

