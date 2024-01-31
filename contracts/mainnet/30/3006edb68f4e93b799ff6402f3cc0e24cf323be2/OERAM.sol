
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: OE x RAM
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////
//                                  //
//                                  //
//    Open edition - Acessmemory    //
//                                  //
//                                  //
//////////////////////////////////////


contract OERAM is ERC1155Creator {
    constructor() ERC1155Creator("OE x RAM", "OERAM") {}
}

