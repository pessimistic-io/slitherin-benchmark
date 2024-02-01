
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: L’esprit de l’eslacier
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                              //
//                                                                                              //
//      "L’esprit de l’eslacier" in French is the equivalent of the event that we could not     //
//    say during the discussion or that we could not think of, and then made us think for       //
//    hours "what did he say, what did I say, but I should have said these things."             //
//                                                                                              //
//                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////


contract SazheaaM101 is ERC721Creator {
    constructor() ERC721Creator(unicode"L’esprit de l’eslacier", "SazheaaM101") {}
}

