
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: CALLIGRAPEPE
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////
//                    //
//                    //
//    CALLIGRAPEPE    //
//                    //
//                    //
////////////////////////


contract CP is ERC1155Creator {
    constructor() ERC1155Creator("CALLIGRAPEPE", "CP") {}
}

