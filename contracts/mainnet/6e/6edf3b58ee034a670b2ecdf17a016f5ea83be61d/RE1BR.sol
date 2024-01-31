
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Re1st Branding
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////
//                        //
//                        //
//    "Re1st" Branding    //
//                        //
//                        //
////////////////////////////


contract RE1BR is ERC721Creator {
    constructor() ERC721Creator("Re1st Branding", "RE1BR") {}
}

