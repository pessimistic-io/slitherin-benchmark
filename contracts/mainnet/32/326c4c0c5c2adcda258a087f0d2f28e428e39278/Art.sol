
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: The Artist
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////
//                                    //
//                                    //
//                                    //
//     ▄▄▄       ██▀███  ▄▄▄█████▓    //
//    ▒████▄    ▓██ ▒ ██▒▓  ██▒ ▓▒    //
//    ▒██  ▀█▄  ▓██ ░▄█ ▒▒ ▓██░ ▒░    //
//    ░██▄▄▄▄██ ▒██▀▀█▄  ░ ▓██▓ ░     //
//     ▓█   ▓██▒░██▓ ▒██▒  ▒██▒ ░     //
//     ▒▒   ▓▒█░░ ▒▓ ░▒▓░  ▒ ░░       //
//      ▒   ▒▒ ░  ░▒ ░ ▒░    ░        //
//      ░   ▒     ░░   ░   ░          //
//          ░  ░   ░                  //
//                                    //
//                                    //
//                                    //
//                                    //
////////////////////////////////////////


contract Art is ERC721Creator {
    constructor() ERC721Creator("The Artist", "Art") {}
}

