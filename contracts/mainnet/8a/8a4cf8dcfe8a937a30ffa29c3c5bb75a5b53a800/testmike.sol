// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Testmike
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////
//            //
//            //
//    test    //
//            //
//            //
////////////////


contract testmike is ERC721Creator {
    constructor() ERC721Creator("Testmike", "testmike") {}
}

