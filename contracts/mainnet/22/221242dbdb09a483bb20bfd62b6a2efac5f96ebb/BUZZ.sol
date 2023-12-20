
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: BuzzDroid
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////////////////////////////////////////
//                                                                             //
//                                                                             //
//    O~~ O~~        O~~     O~~     O~~~~~~~ O~~     O~~~~~~~ O~~             //
//    O~    O~~      O~~     O~~            O~~              O~~               //
//    O~     O~~     O~~     O~~           O~~              O~~                //
//    O~~~ O~        O~~     O~~         O~~              O~~                  //
//    O~     O~~     O~~     O~~        O~~              O~~                   //
//    O~      O~     O~~     O~~      O~~              O~~                     //
//    O~~~~ O~~        O~~~~~        O~~~~~~~~~~~     O~~~~~~~~~~~             //
//                                                                             //
//    O~~~~~         O~~~~~~~             O~~~~          O~~     O~~~~~        //
//    O~~   O~~      O~~    O~~         O~~    O~~       O~~     O~~   O~~     //
//    O~~    O~~     O~~    O~~       O~~        O~~     O~~     O~~    O~~    //
//    O~~    O~~     O~ O~~           O~~        O~~     O~~     O~~    O~~    //
//    O~~    O~~     O~~  O~~         O~~        O~~     O~~     O~~    O~~    //
//    O~~   O~~      O~~    O~~         O~~     O~~      O~~     O~~   O~~     //
//    O~~~~~         O~~      O~~         O~~~~          O~~     O~~~~~        //
//                                                                             //
//                                                                             //
//                                                                             //
/////////////////////////////////////////////////////////////////////////////////


contract BUZZ is ERC721Creator {
    constructor() ERC721Creator("BuzzDroid", "BUZZ") {}
}

