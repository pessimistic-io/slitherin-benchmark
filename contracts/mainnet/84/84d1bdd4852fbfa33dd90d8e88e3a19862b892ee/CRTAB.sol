
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: ContractReader.io Tabs
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////////////////////////
//                                                             //
//                                                             //
//    ContractReader.io Tabs, Our First Feature Release NFT    //
//                                                             //
//                                                             //
/////////////////////////////////////////////////////////////////


contract CRTAB is ERC721Creator {
    constructor() ERC721Creator("ContractReader.io Tabs", "CRTAB") {}
}

