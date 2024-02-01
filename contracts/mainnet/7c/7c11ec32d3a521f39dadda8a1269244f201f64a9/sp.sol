
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Season 2
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                        //
//                                                                                                                        //
//                                                                                                                        //
//                                    sSSs   .S   .S_SSSs     .S_sSSs                                                     //
//                                   d%%SP  .SS  .SS~SSSSS   .SS~YS%%b                                                    //
//                                  d%S'    S%S  S%S   SSSS  S%S   `S%b                                                   //
//                                  S%|     S%S  S%S    S%S  S%S    S%S                                                   //
//                                  S&S     S&S  S%S SSSS%S  S%S    d*S                                                   //
//                                  Y&Ss    S&S  S&S  SSS%S  S&S   .S*S                                                   //
//                                  `S&&S   S&S  S&S    S&S  S&S_sdSSS                                                    //
//                                    `S*S  S&S  S&S    S&S  S&S~YSSY                                                     //
//                                     l*S  S*S  S*S    S&S  S*S                                                          //
//                                    .S*P  S*S  S*S    S*S  S*S                                                          //
//                                  sSS*S   S*S  S*S    S*S  S*S                                                          //
//                                  YSS'    S*S  SSS    S*S  S*S                                                          //
//                                          SP          SP   SP                                                           //
//                                          Y           Y    Y                                                            //
//                                                                                                                        //
//      sSSs    sSSs   .S_SSSs      sSSs    sSSs_sSSs     .S_sSSs          sdSS_SSSSSSbs   .S     S.     sSSs_sSSs        //
//     d%%SP   d%%SP  .SS~SSSSS    d%%SP   d%%SP~YS%%b   .SS~YS%%b         YSSS~S%SSSSSP  .SS     SS.   d%%SP~YS%%b       //
//    d%S'    d%S'    S%S   SSSS  d%S'    d%S'     `S%b  S%S   `S%b             S%S       S%S     S%S  d%S'     `S%b      //
//    S%|     S%S     S%S    S%S  S%|     S%S       S%S  S%S    S%S             S%S       S%S     S%S  S%S       S%S      //
//    S&S     S&S     S%S SSSS%S  S&S     S&S       S&S  S%S    S&S             S&S       S%S     S%S  S&S       S&S      //
//    Y&Ss    S&S_Ss  S&S  SSS%S  Y&Ss    S&S       S&S  S&S    S&S             S&S       S&S     S&S  S&S       S&S      //
//    `S&&S   S&S~SP  S&S    S&S  `S&&S   S&S       S&S  S&S    S&S             S&S       S&S     S&S  S&S       S&S      //
//      `S*S  S&S     S&S    S&S    `S*S  S&S       S&S  S&S    S&S             S&S       S&S     S&S  S&S       S&S      //
//       l*S  S*b     S*S    S&S     l*S  S*b       d*S  S*S    S*S             S*S       S*S     S*S  S*b       d*S      //
//      .S*P  S*S.    S*S    S*S    .S*P  S*S.     .S*S  S*S    S*S             S*S       S*S  .  S*S  S*S.     .S*S      //
//    sSS*S    SSSbs  S*S    S*S  sSS*S    SSSbs_sdSSS   S*S    S*S             S*S       S*S_sSs_S*S   SSSbs_sdSSS       //
//    YSS'      YSSP  SSS    S*S  YSS'      YSSP~YSSY    S*S    SSS             S*S       SSS~SSS~S*S    YSSP~YSSY        //
//                           SP                          SP                     SP                                        //
//                           Y                           Y                      Y                                         //
//                                                                                                                        //
//                                                                                                                        //
//                                                                                                                        //
//                                                                                                                        //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract sp is ERC721Creator {
    constructor() ERC721Creator("Season 2", "sp") {}
}

