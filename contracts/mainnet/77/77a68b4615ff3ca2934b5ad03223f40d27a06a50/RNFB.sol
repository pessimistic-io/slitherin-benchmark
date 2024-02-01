
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: rakuneco fun box
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////////////////
//                                                   //
//                                                   //
//               _                                   //
//     _ __ __ _| | ___   _ _ __   ___  ___ ___      //
//    | '__/ _` | |/ / | | | '_ \ / _ \/ __/ _ \     //
//    | | | (_| |   <| |_| | | | |  __/ (_| (_) |    //
//    |_|  \__,_|_|\_\\__,_|_| |_|\___|\___\___/     //
//                                                   //
//                                                   //
//                                                   //
///////////////////////////////////////////////////////


contract RNFB is ERC721Creator {
    constructor() ERC721Creator("rakuneco fun box", "RNFB") {}
}

