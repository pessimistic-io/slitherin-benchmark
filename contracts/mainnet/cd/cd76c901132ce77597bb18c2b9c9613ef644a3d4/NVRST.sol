
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: NEVEREST Genesis Collection
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////////////////////////////
//                                                                 //
//                                                                 //
//    GENESIS COLLECTION                                           //
//    BY NEVEREST                                                  //
//                                                                 //
//                                                                 //
//            _    .  ,   .           .                            //
//        *  / \_ *  / \_      _  *        *   /\'__        *      //
//          /    \  /    \,   ((        .    _/  /  \  *'.         //
//     .   /\/\  /\/ :' __ \_  `          _^/  ^/    `--.          //
//        /    \/  \  _/  \-'\  NEVEREST   /.' ^_   \_   .'\  *    //
//      /\  .-   `. \/     \ /==~=-=~=-=-;.  _/ \ -. `_/   \       //
//     /  `-.__ ^   / .-'.--\ =-=~_=-=~=^/  _ `--./ .-'  `-        //
//    /jgs     `.  / /       `.~-^=-=~=^=.-'      '-._ `._         //
//                                                                 //
//                                                                 //
/////////////////////////////////////////////////////////////////////


contract NVRST is ERC721Creator {
    constructor() ERC721Creator("NEVEREST Genesis Collection", "NVRST") {}
}

