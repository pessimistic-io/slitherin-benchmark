// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: MOGUTARO
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////
//                          //
//                          //
//     +-+-+-+-+-+-+-+-+    //
//     |M|O|G|U|T|A|R|O|    //
//     +-+-+-+-+-+-+-+-+    //
//                          //
//                          //
//////////////////////////////


contract MOGUTARO is ERC1155Creator {
    constructor() ERC1155Creator("MOGUTARO", "MOGUTARO") {}
}

