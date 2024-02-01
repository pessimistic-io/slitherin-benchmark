
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Visionary NFT Posters
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                          //
//                                                                                                          //
//    I'm Nuwan Shilpa Hennayake, a Psychedelic Visionary Artist from Sri Lanka.                            //
//    I create Digital Mind Trips inspired by Liberal Spiritual Dimensions.                                 //
//                                                                                                          //
//    This collection contains Psychedelic and Visionary Art Posters designed using my Original Artwork.    //
//                                                                                                          //
//    Each Poster is limited to an edition of 111                                                           //
//                                                                                                          //
//    Collect yours today!                                                                                  //
//                                                                                                          //
//                                                                                                          //
//                                                                                                          //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract VAP is ERC721Creator {
    constructor() ERC721Creator("Visionary NFT Posters", "VAP") {}
}

