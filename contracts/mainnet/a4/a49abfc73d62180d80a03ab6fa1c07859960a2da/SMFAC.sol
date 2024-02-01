
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Satsuki Minato Fan Art Collection
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////
//               //
//               //
//    fan art    //
//               //
//               //
///////////////////


contract SMFAC is ERC721Creator {
    constructor() ERC721Creator("Satsuki Minato Fan Art Collection", "SMFAC") {}
}

