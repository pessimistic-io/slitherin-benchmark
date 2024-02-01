
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Essential editions
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                            //
//                                                                                            //
//    The one essential way is in the art - Love what you live, live what you love. Always    //
//                                                                                            //
//                                                                                            //
////////////////////////////////////////////////////////////////////////////////////////////////


contract basic is ERC1155Creator {
    constructor() ERC1155Creator("Essential editions", "basic") {}
}

