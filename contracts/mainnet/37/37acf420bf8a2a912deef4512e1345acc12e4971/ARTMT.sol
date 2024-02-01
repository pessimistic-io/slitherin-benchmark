// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Alexey Tarasov ART Multi-Token
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                  //
//                                                                                                                  //
//              _     _      ___  __  __  ___  __   __    _____     _     ___     _     ___    ___   __   __        //
//             /_\   | |    | __| \ \/ / | __| \ \ / /   |_   _|   /_\   | _ \   /_\   / __|  / _ \  \ \ / /        //
//            / _ \  | |__  | _|   >  <  | _|   \ V /      | |    / _ \  |   /  / _ \  \__ \ | (_) |  \ V /         //
//           /_/ \_\ |____| |___| /_/\_\ |___|   |_|       |_|   /_/ \_\ |_|_\ /_/ \_\ |___/  \___/    \_/          //
//                                                                                                                  //
//             When you acquire an NFT, you become an owner with full rights to use it at your discretion!          //
//                                                                                                                  //
//                                                                                                                  //
//                                                                                                                  //
//                                                                                                                  //
//                                                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract ARTMT is ERC1155Creator {
    constructor() ERC1155Creator("Alexey Tarasov ART Multi-Token", "ARTMT") {}
}

