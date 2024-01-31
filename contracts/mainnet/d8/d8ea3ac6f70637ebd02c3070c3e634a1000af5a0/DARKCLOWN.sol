
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: DARK CLOWN
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////
//                                               //
//                                               //
//    .------------.                             //
//    | IMKATE.ETH |                             //
//    '------------'                             //
//                                               //
//    Creator of the "imkate.eth" collection.    //
//                                               //
//                                               //
//                                               //
///////////////////////////////////////////////////


contract DARKCLOWN is ERC1155Creator {
    constructor() ERC1155Creator("DARK CLOWN", "DARKCLOWN") {}
}

