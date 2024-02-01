
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Half-frame
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////////////////////////////////
//                                                                   //
//                                                                   //
//                                                                   //
//              ___      ___      ___   ___   ___      ___           //
//             /\  \    /\  \    /\__\ /\__\ /\  \    /\  \          //
//            _\:\  \  /::\  \  /:/  //:/  //::\  \  /::\  \         //
//           /::::\__\/::\:\__\/:/__//:/__//::\:\__\/::\:\__\        //
//           \::;;/__/\:\:\/  /\:\  \\:\  \\:\:\/  /\;:::/  /        //
//            \:\__\   \:\/  /  \:\__\\:\__\\:\/  /  |:\/__/         //
//             \/__/    \/__/    \/__/ \/__/ \/__/    \|__|          //
//                                                                   //
//            \ | /      samuelzeller.eth                            //
//           '  _  '     www.samuelzeller.ch                         //
//          -  |_|  -    instagram.com/zellersamuel                  //
//           ' | | '     twitter.com/zellersamuel                    //
//           _,_|___     foundation.app/@zellersamuel                //
//          |   _ []|                                                //
//          |  (O)  |    Thank you for collecting                    //
//          |_______|    my art ✨                                    //
//                                                                   //
//                                                                   //
///////////////////////////////////////////////////////////////////////


contract SZHF is ERC721Creator {
    constructor() ERC721Creator("Half-frame", "SZHF") {}
}

