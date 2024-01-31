
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: PitooPi
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////////////
//                                     //
//                                     //
//                                     //
//     _____ _ _           _____ _     //
//    |  _  |_| |_ ___ ___|  _  |_|    //
//    |   __| |  _| . | . |   __| |    //
//    |__|  |_|_| |___|___|__|  |_|    //
//                                     //
//                                     //
//                                     //
/////////////////////////////////////////


contract P2PI is ERC1155Creator {
    constructor() ERC1155Creator("PitooPi", "P2PI") {}
}

