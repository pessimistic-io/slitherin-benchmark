
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




contract TheOdyssey_CreatedByALIENSWAP is ERC721Creator {
    SalesConfiguration  salesConfig = SalesConfiguration(

0,
1000,
1701495129,
1703223130,
0,
0,
0,
4102444799,
0x0000000000000000000000000000000000000000000000000000000000000000,
0x0198cb155e5dAb88146f48aBA93De02B695491f8
    );

    constructor() ERC721Creator(unicode"The Odyssey", unicode"The Odyssey", 1000000, "https://createx.art/api/v1/createx/metadata/ARBITRUM/7bqfrvce6a5uqbkicnll2548cmn3y0n3/", 
    "https://createx.art/api/v1/createx/collection_url/ARBITRUM/7bqfrvce6a5uqbkicnll2548cmn3y0n3", 0x0198cb155e5dAb88146f48aBA93De02B695491f8, 750, 
    salesConfig
    
    ) {}
}

