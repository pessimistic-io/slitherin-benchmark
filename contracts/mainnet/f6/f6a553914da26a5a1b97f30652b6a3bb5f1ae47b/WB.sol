
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: WB
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////
//          //
//          //
//    WB    //
//          //
//          //
//////////////


contract WB is ERC721Creator {
    constructor() ERC721Creator("WB", "WB") {}
}

