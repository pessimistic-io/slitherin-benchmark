
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: CCLabs
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////////////////
//                                         //
//                                         //
//                                         //
//     ▄▄·  ▄▄· ▄▄▌   ▄▄▄· ▄▄▄▄· .▄▄ ·     //
//    ▐█ ▌▪▐█ ▌▪██•  ▐█ ▀█ ▐█ ▀█▪▐█ ▀.     //
//    ██ ▄▄██ ▄▄██▪  ▄█▀▀█ ▐█▀▀█▄▄▀▀▀█▄    //
//    ▐███▌▐███▌▐█▌▐▌▐█ ▪▐▌██▄▪▐█▐█▄▪▐█    //
//    ·▀▀▀ ·▀▀▀ .▀▀▀  ▀  ▀ ·▀▀▀▀  ▀▀▀▀     //
//                                         //
//                                         //
//                                         //
/////////////////////////////////////////////


contract CCL is ERC1155Creator {
    constructor() ERC1155Creator("CCLabs", "CCL") {}
}

