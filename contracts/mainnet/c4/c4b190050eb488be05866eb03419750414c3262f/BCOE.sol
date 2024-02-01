// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: BC Open Editions
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////
//                   //
//                   //
//      ___  ___     //
//     | _ )/ __|    //
//     | _ | (__     //
//     |___/\___|    //
//                   //
//                   //
//                   //
///////////////////////


contract BCOE is ERC1155Creator {
    constructor() ERC1155Creator("BC Open Editions", "BCOE") {}
}

