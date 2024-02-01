
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: PepeLove❤️
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////
//                                        //
//                                        //
//    __________                          //
//    \______   \ ____ ______   ____      //
//     |     ___// __ \\____ \_/ __ \     //
//     |    |   \  ___/|  |_> >  ___/     //
//     |____|    \___  >   __/ \___  >    //
//                   \/|__|        \/     //
//                                        //
//                                        //
////////////////////////////////////////////


contract Pepe is ERC1155Creator {
    constructor() ERC1155Creator(unicode"PepeLove❤️", "Pepe") {}
}

