
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Editions by Fr_Lehmann
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////
//                              //
//                              //
//    EDITIONS by Fr_Lehmann    //
//                              //
//                              //
//////////////////////////////////


contract EbFrL is ERC1155Creator {
    constructor() ERC1155Creator("Editions by Fr_Lehmann", "EbFrL") {}
}

