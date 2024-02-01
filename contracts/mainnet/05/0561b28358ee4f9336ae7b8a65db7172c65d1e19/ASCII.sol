
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Unknown Portrait
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////
//                        //
//                        //
//       ___________      //
//      /                 //
//     |            |     //
//     |  ____ ____ |     //
//     | |    |    | |    //
//     | |____|____| |    //
//     |            |     //
//     |  ________  |     //
//     | |        | |     //
//     | |________| |     //
//     |            |     //
//      \__________/      //
//                        //
//                        //
////////////////////////////


contract ASCII is ERC1155Creator {
    constructor() ERC1155Creator("Unknown Portrait", "ASCII") {}
}

