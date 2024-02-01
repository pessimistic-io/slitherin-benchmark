
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Forgiveless
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////
//                              //
//                              //
//                              //
//    ,------.,--.              //
//    |  .---'|  |,--. ,--.     //
//    |  `--, |  | \  '  /      //
//    |  |`   |  |  \   '       //
//    `--'    `--'.-'  /        //
//                `---'         //
//                              //
//                              //
//////////////////////////////////


contract Nat is ERC1155Creator {
    constructor() ERC1155Creator("Forgiveless", "Nat") {}
}

