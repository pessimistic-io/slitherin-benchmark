
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Beautiful Singularity
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////////////////
//                                                     //
//                                                     //
//      ___                _   _  __      _            //
//     | _ ) ___ __ _ _  _| |_(_)/ _|_  _| |           //
//     | _ \/ -_) _` | || |  _| |  _| || | |           //
//     |___/\___\__,_|\_,_|\__|_|_|  \_,_|_|           //
//     / __(_)_ _  __ _ _  _| |__ _ _ _(_) |_ _  _     //
//     \__ \ | ' \/ _` | || | / _` | '_| |  _| || |    //
//     |___/_|_||_\__, |\_,_|_\__,_|_| |_|\__|\_, |    //
//                |___/                       |__/     //
//                                                     //
//                                                     //
/////////////////////////////////////////////////////////


contract BeautifulSingularity is ERC721Creator {
    constructor() ERC721Creator("Beautiful Singularity", "BeautifulSingularity") {}
}

