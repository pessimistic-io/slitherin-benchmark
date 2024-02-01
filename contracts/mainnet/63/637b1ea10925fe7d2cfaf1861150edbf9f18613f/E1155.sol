// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: 1155
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////
//         //
//         //
//    a    //
//         //
//         //
/////////////


contract E1155 is ERC1155Creator {
    constructor() ERC1155Creator("1155", "E1155") {}
}

