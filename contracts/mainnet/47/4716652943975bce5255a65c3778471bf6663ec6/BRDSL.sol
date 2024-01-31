
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Boardslide
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                          dddddddd                                             dddddddd                        //
//    BBBBBBBBBBBBBBBBB                                                                     d::::::d                 lllllll   iiii              d::::::d                        //
//    B::::::::::::::::B                                                                    d::::::d                 l:::::l  i::::i             d::::::d                        //
//    B::::::BBBBBB:::::B                                                                   d::::::d                 l:::::l   iiii              d::::::d                        //
//    BB:::::B     B:::::B                                                                  d:::::d                  l:::::l                     d:::::d                         //
//      B::::B     B:::::B   ooooooooooo     aaaaaaaaaaaaa  rrrrr   rrrrrrrrr       ddddddddd:::::d     ssssssssss    l::::l iiiiiii     ddddddddd:::::d     eeeeeeeeeeee        //
//      B::::B     B:::::B oo:::::::::::oo   a::::::::::::a r::::rrr:::::::::r    dd::::::::::::::d   ss::::::::::s   l::::l i:::::i   dd::::::::::::::d   ee::::::::::::ee      //
//      B::::BBBBBB:::::B o:::::::::::::::o  aaaaaaaaa:::::ar:::::::::::::::::r  d::::::::::::::::d ss:::::::::::::s  l::::l  i::::i  d::::::::::::::::d  e::::::eeeee:::::ee    //
//      B:::::::::::::BB  o:::::ooooo:::::o           a::::arr::::::rrrrr::::::rd:::::::ddddd:::::d s::::::ssss:::::s l::::l  i::::i d:::::::ddddd:::::d e::::::e     e:::::e    //
//      B::::BBBBBB:::::B o::::o     o::::o    aaaaaaa:::::a r:::::r     r:::::rd::::::d    d:::::d  s:::::s  ssssss  l::::l  i::::i d::::::d    d:::::d e:::::::eeeee::::::e    //
//      B::::B     B:::::Bo::::o     o::::o  aa::::::::::::a r:::::r     rrrrrrrd:::::d     d:::::d    s::::::s       l::::l  i::::i d:::::d     d:::::d e:::::::::::::::::e     //
//      B::::B     B:::::Bo::::o     o::::o a::::aaaa::::::a r:::::r            d:::::d     d:::::d       s::::::s    l::::l  i::::i d:::::d     d:::::d e::::::eeeeeeeeeee      //
//      B::::B     B:::::Bo::::o     o::::oa::::a    a:::::a r:::::r            d:::::d     d:::::d ssssss   s:::::s  l::::l  i::::i d:::::d     d:::::d e:::::::e               //
//    BB:::::BBBBBB::::::Bo:::::ooooo:::::oa::::a    a:::::a r:::::r            d::::::ddddd::::::dds:::::ssss::::::sl::::::li::::::id::::::ddddd::::::dde::::::::e              //
//    B:::::::::::::::::B o:::::::::::::::oa:::::aaaa::::::a r:::::r             d:::::::::::::::::ds::::::::::::::s l::::::li::::::i d:::::::::::::::::d e::::::::eeeeeeee      //
//    B::::::::::::::::B   oo:::::::::::oo  a::::::::::aa:::ar:::::r              d:::::::::ddd::::d s:::::::::::ss  l::::::li::::::i  d:::::::::ddd::::d  ee:::::::::::::e      //
//    BBBBBBBBBBBBBBBBB      ooooooooooo     aaaaaaaaaa  aaaarrrrrrr               ddddddddd   ddddd  sssssssssss    lllllllliiiiiiii   ddddddddd   ddddd    eeeeeeeeeeeeee      //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
//                                                                                                                                                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract BRDSL is ERC1155Creator {
    constructor() ERC1155Creator("Boardslide", "BRDSL") {}
}

