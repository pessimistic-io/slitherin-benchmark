// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Marble Gallery
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////////////////////////////////////
//                                                                       //
//                                                                       //
//                                      ,,        ,,                     //
//    `7MMM.     ,MMF'                 *MM      `7MM                     //
//      MMMb    dPMM                    MM        MM                     //
//      M YM   ,M MM   ,6"Yb.  `7Mb,od8 MM,dMMb.  MM  .gP"Ya             //
//      M  Mb  M' MM  8)   MM    MM' "' MM    `Mb MM ,M'   Yb            //
//      M  YM.P'  MM   ,pm9MM    MM     MM     M8 MM 8M""""""            //
//      M  `YM'   MM  8M   MM    MM     MM.   ,M9 MM YM.    ,            //
//    .JML. `'  .JMML.`Moo9^Yo..JMML.   P^YbmdP'.JMML.`Mbmmd'            //
//                                                                       //
//                           ,,    ,,                                    //
//      .g8"""bgd          `7MM  `7MM                                    //
//    .dP'     `M            MM    MM                                    //
//    dM'       `  ,6"Yb.    MM    MM  .gP"Ya `7Mb,od8 `7M'   `MF'       //
//    MM          8)   MM    MM    MM ,M'   Yb  MM' "'   VA   ,V         //
//    MM.    `7MMF',pm9MM    MM    MM 8M""""""  MM        VA ,V          //
//    `Mb.     MM 8M   MM    MM    MM YM.    ,  MM         VVV           //
//      `"bmmmdPY `Moo9^Yo..JMML..JMML.`Mbmmd'.JMML.       ,V            //
//                                                        ,V             //
//                                                     OOb"              //
//                                                                       //
//                                                                       //
///////////////////////////////////////////////////////////////////////////


contract ITR8N is ERC721Creator {
    constructor() ERC721Creator("Marble Gallery", "ITR8N") {}
}

