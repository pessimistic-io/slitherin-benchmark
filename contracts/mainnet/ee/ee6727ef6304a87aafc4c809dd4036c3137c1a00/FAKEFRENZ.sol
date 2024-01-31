
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: FakeFrenz Editions
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////
//                                    //
//                                    //
//     (                  )           //
//     )\ )    (       ( /(           //
//    (()/(    )\      )\()) (        //
//     /(_))((((_)(  |((_)\  )\       //
//    (_))_| )\ _ )\ |_ ((_)((_)      //
//    | |_   (_)_\(_)| |/ / | __|     //
//    | __|   / _ \    ' <  | _|      //
//    |_|    /_/ \_\  _|\_\ |___|     //
//                                    //
//                                    //
//                                    //
////////////////////////////////////////


contract FAKEFRENZ is ERC1155Creator {
    constructor() ERC1155Creator("FakeFrenz Editions", "FAKEFRENZ") {}
}

