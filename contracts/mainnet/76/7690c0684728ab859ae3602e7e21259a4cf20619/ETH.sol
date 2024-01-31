
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: aimoon.eth
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////
//                             //
//                             //
//    ethereum main network    //
//                             //
//                             //
/////////////////////////////////


contract ETH is ERC1155Creator {
    constructor() ERC1155Creator("aimoon.eth", "ETH") {}
}

