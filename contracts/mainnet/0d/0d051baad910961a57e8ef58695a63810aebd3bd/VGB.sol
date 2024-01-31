
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Vagabird
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////
//                                   //
//                                   //
//      ___                 ___      //
//     (o o)               (o o)     //
//    (  V  )   Vagabird  (  V  )    //
//    --m-m-----------------m-m--    //
//                                   //
//                                   //
///////////////////////////////////////


contract VGB is ERC721Creator {
    constructor() ERC721Creator("Vagabird", "VGB") {}
}

