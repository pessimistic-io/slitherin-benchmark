
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: ComancheTippie
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////
//                                        //
//                                        //
//           .---.        .-----------    //
//          /     \  __  /    ------      //
//         / /     \(  )/    -----        //
//        //////   ' \/ `   ---           //
//       //// / // :    : ---             //
//      // /   /  /`    '--               //
//     //          //..\\                 //
//            ====UU====UU====            //
//                '//||\\`                //
//                  ''``                  //
//             comanchetippie             //
//                                        //
//                                        //
////////////////////////////////////////////


contract CMT is ERC1155Creator {
    constructor() ERC1155Creator("ComancheTippie", "CMT") {}
}

