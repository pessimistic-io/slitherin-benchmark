
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Test 12/29
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////////
//                                      //
//                                      //
//                                      //
//    ___________              __       //
//    \__    ___/___   _______/  |_     //
//      |    |_/ __ \ /  ___/\   __\    //
//      |    |\  ___/ \___ \  |  |      //
//      |____| \___  >____  > |__|      //
//                 \/     \/            //
//                                      //
//                                      //
//////////////////////////////////////////


contract TEST is ERC721Creator {
    constructor() ERC721Creator("Test 12/29", "TEST") {}
}

