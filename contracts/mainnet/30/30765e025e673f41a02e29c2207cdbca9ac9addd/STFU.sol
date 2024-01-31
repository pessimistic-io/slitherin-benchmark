
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: 6529 SIMPS
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                     //
//                                                                                                                     //
//        .ooo     oooooooo   .oooo.    .ooooo.         .oooooo..o ooooo ooo        ooooo ooooooooo.    .oooooo..o     //
//      .88'      dP""""""" .dP""Y88b  888' `Y88.      d8P'    `Y8 `888' `88.       .888' `888   `Y88. d8P'    `Y8     //
//     d88'      d88888b.         ]8P' 888    888      Y88bo.       888   888b     d'888   888   .d88' Y88bo.          //
//    d888P"Ybo.     `Y88b      .d8P'   `Vbood888       `"Y8888o.   888   8 Y88. .P  888   888ooo88P'   `"Y8888o.      //
//    Y88[   ]88       ]88    .dP'           888'           `"Y88b  888   8  `888'   888   888              `"Y88b     //
//    `Y88   88P o.   .88P  .oP     .o     .88P'       oo     .d8P  888   8    Y     888   888         oo     .d8P     //
//     `88bod8'  `8bd88P'   8888888888   .oP'          8""88888P'  o888o o8o        o888o o888o        8""88888P'      //
//                                                                                                                     //
//                                                                                                                     //
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract STFU is ERC1155Creator {
    constructor() ERC1155Creator("6529 SIMPS", "STFU") {}
}

