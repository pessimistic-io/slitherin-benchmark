// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Claimed Mehretu Print
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////
//           //
//           //
//    CMP    //
//           //
//           //
///////////////


contract CMP is ERC721Creator {
    constructor() ERC721Creator("Claimed Mehretu Print", "CMP") {}
}

