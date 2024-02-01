
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: PixelMagician
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////
//                                        //
//                                        //
//    __________ ____  ___   _____        //
//    \______   \\   \/  /  /     \       //
//     |     ___/ \     /  /  \ /  \      //
//     |    |     /     \ /    Y    \     //
//     |____|    /___/\  \\____|__  /     //
//                     \_/        \/      //
//                                        //
//                                        //
//                                        //
////////////////////////////////////////////


contract PXM is ERC721Creator {
    constructor() ERC721Creator("PixelMagician", "PXM") {}
}

