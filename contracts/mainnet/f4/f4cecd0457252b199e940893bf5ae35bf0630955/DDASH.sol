
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Dookey Dash
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////
//                   //
//                   //
//    Dookey Dash    //
//                   //
//                   //
///////////////////////


contract DDASH is ERC721Creator {
    constructor() ERC721Creator("Dookey Dash", "DDASH") {}
}

