
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: MMM Crypto
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////
//                                         //
//                                         //
//                                         //
//       _____      _____      _____       //
//      /     \    /     \    /     \      //
//     /  \ /  \  /  \ /  \  /  \ /  \     //
//    /    Y    \/    Y    \/    Y    \    //
//    \____|__  /\____|__  /\____|__  /    //
//            \/         \/         \/     //
//                                         //
//                                         //
//                                         //
/////////////////////////////////////////////


contract MMM is ERC721Creator {
    constructor() ERC721Creator("MMM Crypto", "MMM") {}
}

