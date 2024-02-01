
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Monthly Collection [1枚絵NFT Voice Journal]
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////////////////////////////////////////////////
//                                                                         //
//                                                                         //
//     __      __   _                 _                              _     //
//     \ \    / /  (_)               | |                            | |    //
//      \ \  / /__  _  ___ ___       | | ___  _   _ _ __ _ __   __ _| |    //
//       \ \/ / _ \| |/ __/ _ \  _   | |/ _ \| | | | '__| '_ \ / _` | |    //
//        \  / (_) | | (_|  __/ | |__| | (_) | |_| | |  | | | | (_| | |    //
//         \/ \___/|_|\___\___|  \____/ \___/ \__,_|_|  |_| |_|\__,_|_|    //
//                                                                         //
//                                                                         //
//                                                                         //
//                                                                         //
/////////////////////////////////////////////////////////////////////////////


contract MCVJ is ERC1155Creator {
    constructor() ERC1155Creator(unicode"Monthly Collection [1枚絵NFT Voice Journal]", "MCVJ") {}
}

