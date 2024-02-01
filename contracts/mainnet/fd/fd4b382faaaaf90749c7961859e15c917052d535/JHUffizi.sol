
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Julia Uffizi
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////////
//                                            //
//                                            //
//             )                              //
//          ( /(       (    (                 //
//       (  )\())   (  )\ ) )\ ) (    (       //
//       )\((_)\    )\(()/((()/( )\ ( )\      //
//      ((_)_((_)_ ((_)/(_))/(_)|(_))((_)     //
//     _ | | || | | | (_) _(_) _|(_|(_|_)     //
//    | || | __ | |_| ||  _||  _|| |_ / |     //
//     \__/|_||_|\___/ |_|  |_|  |_/__|_|     //
//                                            //
//                                            //
//                                            //
////////////////////////////////////////////////


contract JHUffizi is ERC1155Creator {
    constructor() ERC1155Creator("Julia Uffizi", "JHUffizi") {}
}

