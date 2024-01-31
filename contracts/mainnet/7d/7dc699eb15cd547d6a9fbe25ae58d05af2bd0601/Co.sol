
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Correction
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////
//                                      //
//                                      //
//                                      //
//      ,.-.    .'(    ,.-.    .'(      //
//     /    `,  \  )  /    `,  \  )     //
//     ) ,-.  ) ) (   ) ,-.  ) ) (      //
//    ( /_.` (  \  ) ( /_.` (  \  )     //
//     )   ,  )  ) \  )   ,  )  ) \     //
//     '._. \(    )/  '._. \(    )/     //
//                                      //
//                                      //
//                                      //
//                                      //
//////////////////////////////////////////


contract Co is ERC1155Creator {
    constructor() ERC1155Creator("Correction", "Co") {}
}

