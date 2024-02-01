
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Don't need Darkness
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////
//                                   //
//                                   //
//                                   //
//     ▄▀▀█▄▄   ▄▀▀▄ ▀▄  ▄▀▀█▄▄      //
//    █ ▄▀   █ █  █ █ █ █ ▄▀   █     //
//    ▐ █    █ ▐  █  ▀█ ▐ █    █     //
//      █    █   █   █    █    █     //
//     ▄▀▄▄▄▄▀ ▄▀   █    ▄▀▄▄▄▄▀     //
//    █     ▐  █    ▐   █     ▐      //
//    ▐        ▐        ▐            //
//                                   //
//                                   //
//                                   //
//                                   //
//                                   //
//                                   //
//                                   //
//                                   //
//                                   //
//                                   //
///////////////////////////////////////


contract DND is ERC1155Creator {
    constructor() ERC1155Creator("Don't need Darkness", "DND") {}
}

