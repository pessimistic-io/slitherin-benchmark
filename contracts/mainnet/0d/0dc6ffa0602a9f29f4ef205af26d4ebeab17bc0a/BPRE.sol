
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Bishop Post-Retirement Era
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////
//                   //
//                   //
//    Bishop 2023    //
//                   //
//                   //
///////////////////////


contract BPRE is ERC721Creator {
    constructor() ERC721Creator("Bishop Post-Retirement Era", "BPRE") {}
}

