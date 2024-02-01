
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Socratico
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////////////////////////////
//                                                          //
//                                                          //
//                                                          //
//    ╔═╗┬ ┬┬┬  ┌─┐┌─┐┌─┐┌─┐┬ ┬┬ ┬  ┌─┐┌┐┌┌┬┐  ╔═╗┬─┐┌┬┐    //
//    ╠═╝├─┤││  │ │└─┐│ │├─┘├─┤└┬┘  ├─┤│││ ││  ╠═╣├┬┘ │     //
//    ╩  ┴ ┴┴┴─┘└─┘└─┘└─┘┴  ┴ ┴ ┴   ┴ ┴┘└┘─┴┘  ╩ ╩┴└─ ┴     //
//                                                          //
//                                                          //
//                                                          //
//////////////////////////////////////////////////////////////


contract SCTC is ERC721Creator {
    constructor() ERC721Creator("Socratico", "SCTC") {}
}

