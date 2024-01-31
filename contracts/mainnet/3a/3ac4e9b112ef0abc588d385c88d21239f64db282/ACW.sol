
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Arisa's commissioned works
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////
//                                  //
//                                  //
//    Arisa's commissioned works    //
//                                  //
//                                  //
//////////////////////////////////////


contract ACW is ERC721Creator {
    constructor() ERC721Creator("Arisa's commissioned works", "ACW") {}
}

