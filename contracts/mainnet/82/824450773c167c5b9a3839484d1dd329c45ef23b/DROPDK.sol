
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: DROPs KEK
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////////////
//                                                       //
//                                                       //
//                                                       //
//     ____  _____ _____ _____     _____ _____ _____     //
//    |    \| __  |     |  _  |___|  |  |   __|  |  |    //
//    |  |  |    -|  |  |   __|_ -|    -|   __|    -|    //
//    |____/|__|__|_____|__|  |___|__|__|_____|__|__|    //
//                                                       //
//                                                       //
//                                                       //
///////////////////////////////////////////////////////////


contract DROPDK is ERC1155Creator {
    constructor() ERC1155Creator("DROPs KEK", "DROPDK") {}
}

