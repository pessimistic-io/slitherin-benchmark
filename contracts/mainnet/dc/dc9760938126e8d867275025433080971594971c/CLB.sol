
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: CRYPTOLEO BALLOON
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////
//                         //
//                         //
//    CRYPTOLEO BALLOON    //
//                         //
//                         //
/////////////////////////////


contract CLB is ERC1155Creator {
    constructor() ERC1155Creator("CRYPTOLEO BALLOON", "CLB") {}
}

