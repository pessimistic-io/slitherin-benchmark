
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Sakura
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////
//                    //
//                    //
//    SakuraSakura    //
//                    //
//                    //
////////////////////////


contract Sakura is ERC1155Creator {
    constructor() ERC1155Creator("Sakura", "Sakura") {}
}

