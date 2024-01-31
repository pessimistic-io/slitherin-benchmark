
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: BROKEN HEARTS
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////
//                         //
//                         //
//    What's the point?    //
//                         //
//                         //
/////////////////////////////


contract BH is ERC1155Creator {
    constructor() ERC1155Creator("BROKEN HEARTS", "BH") {}
}

