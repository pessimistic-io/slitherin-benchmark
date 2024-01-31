
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Cute Ugly Animals
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////
//                                        //
//                                        //
//    🅲🆄🆃🅴 🆄🅶🅻🆈 🅰🅽🅸🅼🅰🅻🆂    //
//                                        //
//                                        //
////////////////////////////////////////////


contract CUA is ERC1155Creator {
    constructor() ERC1155Creator("Cute Ugly Animals", "CUA") {}
}

