
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: MutantApeYC
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////
//            //
//            //
//    MAYC    //
//            //
//            //
////////////////


contract MAYC is ERC721Creator {
    constructor() ERC721Creator("MutantApeYC", "MAYC") {}
}

