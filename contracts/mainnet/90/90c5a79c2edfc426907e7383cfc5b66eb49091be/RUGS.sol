
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: FREEDOMTORUG
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////
//                                    //
//                                    //
//    _____   ____________/  |_       //
//     /     \ /  _ \_  __ \   __\    //
//    |  Y Y  (  <_> )  | \/|  |      //
//    |__|_|  /\____/|__|   |__|      //
//          \/                        //
//                                    //
//                                    //
////////////////////////////////////////


contract RUGS is ERC721Creator {
    constructor() ERC721Creator("FREEDOMTORUG", "RUGS") {}
}

