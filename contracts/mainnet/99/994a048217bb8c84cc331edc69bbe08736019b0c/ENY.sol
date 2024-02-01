
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Epicenter of the New Year.
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////////
//                                            //
//                                            //
//                                            //
//     __   __    _           _               //
//     \ \ / /__ | |__   ___ | |__   ___      //
//      \ V / _ \| '_ \ / _ \| '_ \ / _ \     //
//       | | (_) | | | | (_) | | | | (_) |    //
//       |_|\___/|_| |_|\___/|_| |_|\___/     //
//                                            //
//                                            //
//                                            //
//                                            //
////////////////////////////////////////////////


contract ENY is ERC1155Creator {
    constructor() ERC1155Creator("Epicenter of the New Year.", "ENY") {}
}

