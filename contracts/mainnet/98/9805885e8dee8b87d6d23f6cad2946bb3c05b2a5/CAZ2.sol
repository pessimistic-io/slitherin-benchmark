
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: CazArt 2.0
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////
//                  //
//                  //
//    CAZART 2.0    //
//                  //
//                  //
//////////////////////


contract CAZ2 is ERC1155Creator {
    constructor() ERC1155Creator("CazArt 2.0", "CAZ2") {}
}

