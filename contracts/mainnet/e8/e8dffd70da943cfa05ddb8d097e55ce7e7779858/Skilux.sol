
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Skilux
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////
//              //
//              //
//    Skilux    //
//              //
//              //
//////////////////


contract Skilux is ERC721Creator {
    constructor() ERC721Creator("Skilux", "Skilux") {}
}

