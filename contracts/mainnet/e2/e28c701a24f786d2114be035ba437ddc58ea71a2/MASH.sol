
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: MASH ART
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////////////
//                                     //
//                                     //
//    This is script is for airdrop    //
//                                     //
//                                     //
/////////////////////////////////////////


contract MASH is ERC1155Creator {
    constructor() ERC1155Creator("MASH ART", "MASH") {}
}

