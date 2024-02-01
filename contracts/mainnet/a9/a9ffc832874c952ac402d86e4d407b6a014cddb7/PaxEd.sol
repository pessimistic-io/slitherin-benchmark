
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: PaxRomanEds
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////////////////
//                                         //
//                                         //
//                                         //
//                                         //
//      ____            _____    _         //
//     |  _ \ __ ___  _| ____|__| |        //
//     | |_) / _` \ \/ /  _| / _` |        //
//     |  __/ (_| |>  <| |__| (_| |        //
//     |_|   \__,_/_/\_\_____\__,_|        //
//                                         //
//                                         //
//                                         //
//                                         //
//                                         //
//                                         //
/////////////////////////////////////////////


contract PaxEd is ERC1155Creator {
    constructor() ERC1155Creator("PaxRomanEds", "PaxEd") {}
}

