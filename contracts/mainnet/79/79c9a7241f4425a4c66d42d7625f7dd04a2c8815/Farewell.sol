// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Farewell Messages For DD
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////
//                                                    //
//                                                    //
//    We create this NFT as an eternal storage        //
//    of the farewell messages for our beloved DD.    //
//                                                    //
//                  -- From members of JP BC team.    //
//                                                    //
//                                                    //
////////////////////////////////////////////////////////


contract Farewell is ERC721Creator {
    constructor() ERC721Creator("Farewell Messages For DD", "Farewell") {}
}

