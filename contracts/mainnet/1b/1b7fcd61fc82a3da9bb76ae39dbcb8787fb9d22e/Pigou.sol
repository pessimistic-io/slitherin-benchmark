
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Pigou's first contract
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////
//             //
//             //
//    Pigou    //
//             //
//             //
/////////////////


contract Pigou is ERC721Creator {
    constructor() ERC721Creator("Pigou's first contract", "Pigou") {}
}

