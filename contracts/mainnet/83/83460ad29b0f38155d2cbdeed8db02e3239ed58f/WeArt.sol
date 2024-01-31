
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: We are the Art
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////////////////////////////////////////////////
//                                                                                   //
//                                                                                   //
//    Art is looking and seeing the world differently.                               //
//                                                                                   //
//    Blockchain creates a radical shift in ways of seeing by creating community     //
//    in a new way.                                                                  //
//                                                                                   //
//    To me the art is not the monkey picture,                                       //
//    the lines on a computer screen are not fundamentally different                 //
//    to many other lines that have been drawn on screens;                           //
//    the monkey picture itself doesn't cause me to see the world in a new way.      //
//                                                                                   //
//    What does fundamentally shift my perspective is that the token                 //
//    has caused a community of people who care about the collection,                //
//    to me the community is the art that changes how I see the world.               //
//                                                                                   //
//    The art is not a jpeg, the art is us.                                          //
//                                                                                   //
//    I am creating this series to celebrate all of us who contribute.               //
//                                                                                   //
//    We are the art.                                                                //
//                                                                                   //
//                                                                                   //
///////////////////////////////////////////////////////////////////////////////////////


contract WeArt is ERC721Creator {
    constructor() ERC721Creator("We are the Art", "WeArt") {}
}

