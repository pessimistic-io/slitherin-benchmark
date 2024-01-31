
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Nom CX
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////
//                                     //
//                                     //
//                                     //
//     _______  _________ ____  ___    //
//     \      \ \_   ___ \\   \/  /    //
//     /   |   \/    \  \/ \     /     //
//    /    |    \     \____/     \     //
//    \____|__  /\______  /___/\  \    //
//            \/        \/      \_/    //
//                                     //
//                                     //
//                                     //
/////////////////////////////////////////


contract NCX is ERC721Creator {
    constructor() ERC721Creator("Nom CX", "NCX") {}
}

