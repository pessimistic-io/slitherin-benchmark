
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Kunstloch
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////
//                    //
//                    //
//     __   .__       //
//    |  | _|  |      //
//    |  |/ /  |      //
//    |    <|  |__    //
//    |__|_ \____/    //
//         \/         //
//                    //
//                    //
////////////////////////


contract Kl is ERC1155Creator {
    constructor() ERC1155Creator("Kunstloch", "Kl") {}
}

