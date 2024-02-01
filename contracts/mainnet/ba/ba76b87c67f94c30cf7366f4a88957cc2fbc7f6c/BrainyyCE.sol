// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Brainyy collections & editions
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

/////////////////////////////////////////////////////////////////
//                                                             //
//                                                             //
//                                                             //
//       (                                       (             //
//     ( )\  (       )  (          (     (       )\   (        //
//     )((_) )(   ( /(  )\   (     )\ )  )\ )  (((_)  )\       //
//    ((_)_ (()\  )(_))((_)  )\ ) (()/( (()/(  )\___ ((_)      //
//     | _ ) ((_)((_)_  (_) _(_/(  )(_)) )(_))((/ __|| __|     //
//     | _ \| '_|/ _` | | || ' \))| || || || | | (__ | _|      //
//     |___/|_|  \__,_| |_||_||_|  \_, | \_, |  \___||___|     //
//                                 |__/  |__/                  //
//                                                             //
//                                                             //
/////////////////////////////////////////////////////////////////


contract BrainyyCE is ERC1155Creator {
    constructor() ERC1155Creator("Brainyy collections & editions", "BrainyyCE") {}
}

