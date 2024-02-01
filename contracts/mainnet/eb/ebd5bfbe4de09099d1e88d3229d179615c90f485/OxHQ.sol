
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: 0xHQ Hall Pass
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////////
//                                             //
//                                             //
//    _______           ___ ___ ________       //
//    \   _  \ ___  ___/   |   \\_____  \      //
//    /  /_\  \\  \/  /    ~    \/  / \  \     //
//    \  \_/   \>    <\    Y    /   \_/.  \    //
//     \_____  /__/\_ \\___|_  /\_____\ \_/    //
//           \/      \/      \/        \__>    //
//                                             //
//                                             //
/////////////////////////////////////////////////


contract OxHQ is ERC721Creator {
    constructor() ERC721Creator("0xHQ Hall Pass", "OxHQ") {}
}

