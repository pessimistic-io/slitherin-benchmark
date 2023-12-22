
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




contract CreatedByALIENSWAP is ERC721Creator {
    SalesConfiguration  salesConfig = SalesConfiguration(

100000000000000,
1,
1701524423,
4102444799,
0,
0,
0,
4102444799,
0x0000000000000000000000000000000000000000000000000000000000000000,
0x18667149803d8a0Ad6BC1705501B8de80b0aF663
    );

    constructor() ERC721Creator(unicode"瑜伽少女", unicode"yjsn", 1000, "https://createx.art/api/v1/createx/metadata/ARBITRUM/sikcs7eoeshfqhlflk7olshd0yc1gtgt/", 
    "https://createx.art/api/v1/createx/collection_url/ARBITRUM/sikcs7eoeshfqhlflk7olshd0yc1gtgt", 0x18667149803d8a0Ad6BC1705501B8de80b0aF663, 100, 
    salesConfig
    
    ) {}
}

