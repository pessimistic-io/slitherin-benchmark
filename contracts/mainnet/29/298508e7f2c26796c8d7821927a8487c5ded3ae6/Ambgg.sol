
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Ambassadorsgg
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////////////////////////////////////////////////
//                                                                              //
//                                                                              //
//    This is a test claim mint page for Ambassadors gg. This is unofficial.    //
//                                                                              //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////


contract Ambgg is ERC721Creator {
    constructor() ERC721Creator("Ambassadorsgg", "Ambgg") {}
}

