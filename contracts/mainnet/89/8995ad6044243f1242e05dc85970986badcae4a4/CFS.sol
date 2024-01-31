// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Claimed Framed Schematic
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////
//           //
//           //
//    CFS    //
//           //
//           //
///////////////


contract CFS is ERC721Creator {
    constructor() ERC721Creator("Claimed Framed Schematic", "CFS") {}
}

