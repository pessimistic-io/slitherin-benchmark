
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: PNG
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////
//           //
//           //
//    png    //
//           //
//           //
///////////////


contract PNG is ERC1155Creator {
    constructor() ERC1155Creator("PNG", "PNG") {}
}

