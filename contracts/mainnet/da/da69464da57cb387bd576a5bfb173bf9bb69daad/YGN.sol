// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: You Get Nothing
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////////////////
//                                                           //
//                                                           //
//    When you mint this, just remember, you get nothing.    //
//                                                           //
//                                                           //
///////////////////////////////////////////////////////////////


contract YGN is ERC1155Creator {
    constructor() ERC1155Creator("You Get Nothing", "YGN") {}
}

