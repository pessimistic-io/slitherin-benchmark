
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Zankurami
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////////////
//                                                       //
//                                                       //
//    ///////////////////////////////////////////////    //
//    //OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO//    //
//    //OOOO                                   OOOO//    //
//    //OOO                                     OOO//    //
//    //O     ____..--'   ____    ,---.   .--.    O//    //
//    //O    |        | .'  __ `. |    \  |  |    O//    //
//    //O    |   .-'  '/   '  \  \|  ,  \ |  |    O//    //
//    //O    |.-'.'   /|___|  /  ||  |\_ \|  |    O//    //
//    //O       /   _/    _.-`   ||  _( )_\  |    O//    //
//    //O     .'._( )_ .'   _    || (_ o _)  |    O//    //
//    //O   .'  (_'o._)|  _( )_  ||  (_,_)\  |    O//    //
//    //O   |    (_,_)|\ (_ o _) /|  |    |  |    O//    //
//    //O   |_________| '.(_,_).' '--'    '--'    O//    //
//    //O                                         O//    //
//    //OOO                                     OOO//    //
//    //OOOO                                   OOOO//    //
//    //OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO//    //
//    ///////////////////////////////////////////////    //
//                                                       //
//                                                       //
//                                                       //
///////////////////////////////////////////////////////////


contract ZAN is ERC1155Creator {
    constructor() ERC1155Creator("Zankurami", "ZAN") {}
}

