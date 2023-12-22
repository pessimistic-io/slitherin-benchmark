// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: CHAT3.ONE FREEMINT CLASS A
/// @author: chat3.one

import "./ERC721Creator.sol";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                             //
//                                                                                                                             //
//    The token is free to mint to users. It is required for participants to join a meeting/conference on https://chat3.one    //
//                                                                                                                             //
//                                                                                                                             //
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract CHAT3A is ERC721Creator {
    constructor() ERC721Creator("CHAT3.ONE FREEMINT CLASS A", "CHAT3A") {}
}

