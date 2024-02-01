
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: The Oblivion Queen
/// @author: manifold.xyz

import "./ERC721Creator.sol";

/////////////////////////////////////////////////////////////////////////////////////////
//                                                                                     //
//                                                                                     //
//    ___    ___     _  __       ___     ___  _           _      ___ ___               //
//     ) )_) )_     / ) )_)  )    ) \  /  )  / ) )\ )    / ) / / )_  )_  )\ )          //
//    ( ( ( (__    (_/ /__) (__ _(_  \/ _(_ (_/ (  (    (_X (_/ (__ (__ (  (           //
//                                                                                     //
//                                                                                     //
//                                                                                     //
/////////////////////////////////////////////////////////////////////////////////////////


contract TOQ is ERC721Creator {
    constructor() ERC721Creator("The Oblivion Queen", "TOQ") {}
}

