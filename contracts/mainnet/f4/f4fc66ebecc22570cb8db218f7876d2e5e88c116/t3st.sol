
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: t3stn3t
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////
//                                       //
//                                       //
//    An exercise of the human brain.    //
//                                       //
//                                       //
///////////////////////////////////////////


contract t3st is ERC721Creator {
    constructor() ERC721Creator("t3stn3t", "t3st") {}
}

