
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Monkey
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////
//         //
//         //
//    .    //
//         //
//         //
/////////////


contract BAYC is ERC721Creator {
    constructor() ERC721Creator("Monkey", "BAYC") {}
}

