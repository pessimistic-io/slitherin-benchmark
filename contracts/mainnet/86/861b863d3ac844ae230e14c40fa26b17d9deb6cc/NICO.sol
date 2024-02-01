
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: nico PFP collection
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////////
//                                           //
//                                           //
//    .__                                    //
//    |  |__ _____  ______ ______ ___.__.    //
//    |  |  \\__  \ \____ \\____ <   |  |    //
//    |   Y  \/ __ \|  |_> >  |_> >___  |    //
//    |___|  (____  /   __/|   __// ____|    //
//         \/     \/|__|   |__|   \/         //
//                                           //
//                                           //
///////////////////////////////////////////////


contract NICO is ERC721Creator {
    constructor() ERC721Creator("nico PFP collection", "NICO") {}
}

