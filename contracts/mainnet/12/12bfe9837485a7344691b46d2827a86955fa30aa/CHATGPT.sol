
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: chatgpt.eth
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////
//                   //
//                   //
//    chatgpt.eth    //
//                   //
//                   //
///////////////////////


contract CHATGPT is ERC721Creator {
    constructor() ERC721Creator("chatgpt.eth", "CHATGPT") {}
}

