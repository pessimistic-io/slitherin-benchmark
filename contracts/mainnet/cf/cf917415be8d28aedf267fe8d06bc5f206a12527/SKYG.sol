
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: SAKUYAGenesis
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////
//                           //
//                           //
//    Sakuya Genesis Pass    //
//                           //
//                           //
///////////////////////////////


contract SKYG is ERC1155Creator {
    constructor() ERC1155Creator("SAKUYAGenesis", "SKYG") {}
}

