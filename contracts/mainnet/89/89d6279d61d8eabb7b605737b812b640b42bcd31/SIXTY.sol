
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: The Glitchin 60s
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////
//                                          //
//                                          //
//          ___.    _____                   //
//    _____ \_ |___/ ____\______  ____      //
//    \__  \ | __ \   __\\_  __ \/  _ \     //
//     / __ \| \_\ \  |   |  | \(  <_> )    //
//    (____  /___  /__|   |__|   \____/     //
//         \/    \/                         //
//                                          //
//                                          //
//////////////////////////////////////////////


contract SIXTY is ERC1155Creator {
    constructor() ERC1155Creator("The Glitchin 60s", "SIXTY") {}
}

