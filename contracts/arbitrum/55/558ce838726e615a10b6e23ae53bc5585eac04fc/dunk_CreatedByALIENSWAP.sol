
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




contract dunk_CreatedByALIENSWAP is ERC721Creator {
    SalesConfiguration  salesConfig = SalesConfiguration(

100000000000000,
1,
1701386488,
1708557668,
0,
0,
0,
4102444799,
0x0000000000000000000000000000000000000000000000000000000000000000,
0x610591Cc9D70b02775f194Ef42162725b94D740b
    );

    constructor() ERC721Creator(unicode"dunk", unicode"dnk", 1000000, "https://createx.art/api/v1/createx/metadata/ARBITRUM/41qqtni0l6tc5vpurisksiybo0dje32f/", 
    "https://createx.art/api/v1/createx/collection_url/ARBITRUM/41qqtni0l6tc5vpurisksiybo0dje32f", 0x610591Cc9D70b02775f194Ef42162725b94D740b, 1, 
    salesConfig
    
    ) {}
}

