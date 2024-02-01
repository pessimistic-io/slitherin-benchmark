// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Chat3 Free Mint Trial
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////
//                             //
//                             //
//    Chat3 free mint trial    //
//                             //
//                             //
/////////////////////////////////


contract CHAT3FMT is ERC721Creator {
    constructor() ERC721Creator("Chat3 Free Mint Trial", "CHAT3FMT") {}
}

