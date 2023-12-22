
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




contract statiob_CreatedByALIENSWAP is ERC721Creator {
    SalesConfiguration  salesConfig = SalesConfiguration(

30000000000000,
1,
1701347732,
1702643620,
0,
0,
0,
4102444799,
0x0000000000000000000000000000000000000000000000000000000000000000,
0x259E88fbb9a6b2FF78e840B6483D98D7678D033e
    );

    constructor() ERC721Creator(unicode"statiob", unicode"st", 2, "https://createx.art/api/v1/createx/metadata/ARBITRUM/3gzz1qhwyvozv29wfc9ypg1q2u0xtdq9/", 
    "https://createx.art/api/v1/createx/collection_url/ARBITRUM/3gzz1qhwyvozv29wfc9ypg1q2u0xtdq9", 0x259E88fbb9a6b2FF78e840B6483D98D7678D033e, 100, 
    salesConfig
    
    ) {}
}

