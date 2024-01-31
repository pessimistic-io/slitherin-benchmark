// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Checks Your Boobs
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////////////////////////////////
//                                                                    //
//                                                                    //
//    50% of the funds received from the mint will be sent to the     //
//    National Breast Cancer Foundation.                              //
//                                                                    //
//                                                                    //
////////////////////////////////////////////////////////////////////////


contract CYB is ERC1155Creator {
    constructor() ERC1155Creator("Checks Your Boobs", "CYB") {}
}

