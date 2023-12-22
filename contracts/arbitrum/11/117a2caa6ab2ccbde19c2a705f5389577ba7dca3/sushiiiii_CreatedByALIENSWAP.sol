
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/////////////////////////////////////////////////////////
//  all-in-one NFT generator at https://alienswap.xyz  //
/////////////////////////////////////////////////////////

import "./ERC721Creator.sol";



///////////////////////////////////////////////////
//   ___  _ _                                    //
//  / _ \| (_)                                   //
// / /_\ \ |_  ___ _ __  _____      ____ _ _ __  //
// |  _  | | |/ _ \ '_ \/ __\ \ /\ / / _` | '_ \ //
// | | | | | |  __/ | | \__ \ V  V / (_| | |_) |//
// \_| |_/_|_|\___|_| |_|___/ \_/\_/ \__,_| .__/ //
//                                        | |    //
//                                        |_|    //
///////////////////////////////////////////////////




contract sushiiiii_CreatedByALIENSWAP is ERC721Creator {
    SalesConfiguration  salesConfig = SalesConfiguration(

100000000000000,
5,
1701194612,
4102444799,
0,
0,
0,
4102444799,
0x0000000000000000000000000000000000000000000000000000000000000000,
0xc7Dcd128abD9d239F4A6d5856B42Af7F2Ae605C8
    );

    constructor() ERC721Creator(unicode"sushiiiii", unicode"sush", 1000000, "https://createx.art/api/v1/createx/metadata/ARBITRUM/4fstgh898a25uzdf93laov17v83ywcor/", 
    "https://createx.art/api/v1/createx/collection_url/ARBITRUM/4fstgh898a25uzdf93laov17v83ywcor", 0xc7Dcd128abD9d239F4A6d5856B42Af7F2Ae605C8, 500, 
    salesConfig
    
    ) {}
}

