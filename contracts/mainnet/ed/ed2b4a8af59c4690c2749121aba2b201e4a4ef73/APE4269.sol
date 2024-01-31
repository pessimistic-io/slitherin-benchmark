
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: APE4269
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////
//                                          //
//                                          //
//    APE4269 Artwork                       //
//    https://opensea.io/ape4269/created    //
//    No Rights Reserved - CC0              //
//                                          //
//    Contact                               //
//    https://twitter.com/ape4269           //
//                                          //
//                                          //
//                                          //
//////////////////////////////////////////////


contract APE4269 is ERC1155Creator {
    constructor() ERC1155Creator("APE4269", "APE4269") {}
}

