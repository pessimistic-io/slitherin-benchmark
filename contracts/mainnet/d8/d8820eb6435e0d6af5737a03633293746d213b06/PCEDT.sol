
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Editions by Paolo Curtoni
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////
//                     //
//                     //
//     _ _ _ _ _       //
//    |_|_|_|_|_|      //
//    |_|_|#|_|_|      //
//    |_|_|_|#|_|      //
//    |_|#|#|#|_|      //
//    |_|_|_|_|_|      //
//                     //
//       Paolo         //
//      Curtoni        //
//     -editions-      //
//                     //
//                     //
/////////////////////////


contract PCEDT is ERC1155Creator {
    constructor() ERC1155Creator("Editions by Paolo Curtoni", "PCEDT") {}
}

