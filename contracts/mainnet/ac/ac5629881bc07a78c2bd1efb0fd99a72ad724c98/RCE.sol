
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Riccardo Cagnotto Editions
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////
//                             //
//                             //
//     ###     ##    ####      //
//     #  #   #  #   #         //
//     #  #   #      ###       //
//     ###    #      #         //
//     #  #   #  #   #         //
//     #  #    ##    ####      //
//                             //
//                             //
/////////////////////////////////


contract RCE is ERC1155Creator {
    constructor() ERC1155Creator("Riccardo Cagnotto Editions", "RCE") {}
}

