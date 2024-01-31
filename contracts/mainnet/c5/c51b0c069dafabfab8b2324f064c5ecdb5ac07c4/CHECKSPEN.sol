
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Checkspen
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////////////////
//                                                     //
//                                                     //
//                                                     //
//     __        ___  __        __   __   ___          //
//    /  ` |__| |__  /  ` |__/ /__` |__) |__  |\ |     //
//    \__, |  | |___ \__, |  \ .__/ |    |___ | \|     //
//                                                     //
//                                                     //
//                                                     //
//                                                     //
/////////////////////////////////////////////////////////


contract CHECKSPEN is ERC721Creator {
    constructor() ERC721Creator("Checkspen", "CHECKSPEN") {}
}

