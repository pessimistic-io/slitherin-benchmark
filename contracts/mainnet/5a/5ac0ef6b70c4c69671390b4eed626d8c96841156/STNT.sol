
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Seize The Nakamoto Trippy
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                        //
//                                                                                        //
//    "We have proposed a system for electronic transactions without relying on trust"    //
//                                                                                        //
//                                                                                        //
////////////////////////////////////////////////////////////////////////////////////////////


contract STNT is ERC1155Creator {
    constructor() ERC1155Creator("Seize The Nakamoto Trippy", "STNT") {}
}

