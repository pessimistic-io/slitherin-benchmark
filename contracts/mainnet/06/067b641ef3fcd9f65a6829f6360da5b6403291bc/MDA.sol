
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Million Dollar Artwork💲
/// @author: manifold.xyz

import "./ERC721Creator.sol";

///////////////////////////////////////////////
//                                           //
//                                           //
//                                           //
//     _   .-')    _ .-') _     ('-.         //
//    ( '.( OO )_ ( (  OO) )   ( OO ).-.     //
//     ,--.   ,--.)\     .'_   / . --. /     //
//     |   `.'   | ,`'--..._)  | \-.  \      //
//     |         | |  |  \  '.-'-'  |  |     //
//     |  |'.'|  | |  |   ' | \| |_.'  |     //
//     |  |   |  | |  |   / :  |  .-.  |     //
//     |  |   |  | |  '--'  /  |  | |  |     //
//     `--'   `--' `-------'   `--' `--'     //
//                                           //
//                                           //
//                                           //
///////////////////////////////////////////////


contract MDA is ERC721Creator {
    constructor() ERC721Creator(unicode"Million Dollar Artwork💲", "MDA") {}
}

