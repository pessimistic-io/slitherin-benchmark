
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: HAKUMAI Special GOHAN
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                                                                                //
//                                                                                                                                                                                                                //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMD!               (WMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM$                   MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM~                   dMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM~                   dMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM""""""""""""""TWMMMMMMMMMMMM~     `    `        dMMMMMMMMMMMM9""""""""""""""YMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#                                                                        `                                                               -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#                                                             `     `       `                                                            -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMN.                 -MMMMMMMMM~                   dMMMMMMMM@                  .MMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMN                  (MMMMMMMM~     `       `     dMMMMMMM#                  .MMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMb                  ?MMMMMMM~         `         dMMMMMM#                  .MMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMb   `  `  `  `     ?MMMMMM~  `             `  dMMMMMM`       `  `  `   .MMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMb              `   vMMMMM~      `     `      dMMMMM!                 .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMp                  4MMMM~                   dMMMM'                 .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMp                  UMMM~  `      `     `   dMMM'        `        .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM|  `  `  `         WMM~     `             dMM^            `  `  MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM,          `  `   (MM~            `      dMN.                 dMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNggggggggggggg+gMMMM~        `      `   dMMMNg+gggggggggggggMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMM"""""""""""""""""""""""""""""""`   `               ?""""""""""""""""""""""""""""""HMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMM#                                        `    `                                        (MMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMF                                                `  `                                   MMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMM]                                  `                                                    MMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMM]                                     `   `  `                                          MMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMM]                        `  `  `                `     `  `  `  `  `             `       MMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMM]    `  `  `  `  `  `             `                `                 `  `  `            MMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMb                      `             `  `    `                                `    `   .MMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMNJ.............                                                         .............+MMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF           `  `  `.~       `     `   ` u   `  `  `  `     ,MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM@     `  `         .M~   `      `        db              `   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM`                 .MM~                   dMb                  ?MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM!             `   .MMM~      `        `   dMMp                  4MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM^     `     `      dMMM~  `         `      dMMM,  `  `  `         WMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMt         `        JMMMM~         `         dMMMM,          `       HMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMF                  -MMMMM~     `             dMMMMN.            `    .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMMMF       `          .MMMMMM~              `    dMMMMMN.                 ,MMMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMMMMMMMMMMMMMMMMMMMMMM@           `   `  .MMMMMMM~   `    `        ` dMMMMMMR   `  `           ,MMMMMMMMMMMMMMMMMMMMMMMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMMD                 /M#                  .MMMMMMMM~           `       dMMMMMMMb        `  `      (M#'                 UMMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMMF                   (`       `         .MMMMMMMMM~              `    dMMMMMMMMp                  ?`                   MMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMM]                               `  `   MMMMMMMMMM~    `  `           dMMMMMMMMM|            `                         MMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    MMMMM]                                     dMMMMMMMMMM~          `        dMMMMMMMMMM,  `                                  MMMMMF   -MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMB"~````````````?7MM#    MMMMM]                         `           `````````_?`               `   ?!``````````     `  `     `                      MMMMMF   -MM@^`````````````?TMMMMMMMMMMMM    //
//    MMMMMMMMMMM#                  H#    MMMMM]                   `        `                       `                                                                MMMMMF   -M$                 ,MMMMMMMMMMM    //
//    MMMMMMMMMMMMp                  S    MMMMM]    `  `  `  `  `     `        `         `             `  `  `            `                `       `  `  `  `  `  `  MMMMMF   -%                 .MMMMMMMMMMMM    //
//    MMMMMMMMMMMMMx                      MMMMM]                   ,MMMMMMMM#                  .,                `  q                  (MMMMMMMM#                    MMMMMF                      dMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMM,                     MMMMM]                   ,MMMMMMM#      `  `      ` .MN,                 .MR       `   `  `   ?MMMMMMM#                    MMMMMF                     dMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMM,                    MMMMM]    `              ,MMMMMMM`            `    .MMMMNNggggggggggggggMMMMb  `               ?MMMMMM#                    MMMMMF  `                 JMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMN,                   MMMMM]        `  `  `    ,MMMMMM`                 .MMMMMMMMMMMMMMMMMMMMMMMMMMb                  ?MMMMM#   `  `  `  `  `    MMMMMF       `           (MMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMN,           `  `   MMMMM]                   ,MMMMM!        `        .MMMMMMMMMMMMMMMMMMMMMMMMMMMMb    `  `          TMMMM#                    MMMMMF          `      `-MMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMN.      `          ,MMMM]   `            `  ,MMMM'            `  ` .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMp         `  `     UMMM#                 `  MMMMF     `        `   .MMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMN.                 ,MMM]      `            ,MMM^        `        .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM[                  UMM#   `                MMMF                  .MMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMN        `         -MM]         `  `      ,MM%                  dMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM,   `         `    MM#       `  `  `      MM#     `    `       .MMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMh.  `      `      .MM]               `   ,MML                 JMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM,                .MM#                `   MMN.            `  `.MMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#  ` MMMMM]   `               ,MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#    `               MMMMMF   .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMM9""""""""""""""""""""""    """""'      `    `       .""""""""""""""""""""""""""""""""MMMMMMMMMMMM#""""""""""""""""""""""""""""""""             `      7""""^   ,"""""""""""""""""""""TWMMMMMMMM    //
//    MMMMMMMM`                                                `                                     MMMMMMMMMMF                                   `    `  `                                          JMMMMMMM    //
//    MMMMMMM#                                     `    `                                            dMMMMMMMMM}                                                 `                                    ,MMMMMMM    //
//    MMMMMMM#                                             `      `                                  dMMMMMMMMM{                                                    `                                 ,MMMMMMM    //
//    MMMMMMM#                           `    `  `             `                      `   `          dMMMMMMMMM{                               `  `  `       `            `  `                        ,MMMMMMM    //
//    MMMMMMM#                                       `               `  `       `  `         `  `    dMMMMMMMMM{    `    `  `  `  `  `  `  `            `       `                                     ,MMMMMMM    //
//    MMMMMMM#     `                `  `    `           `  `               `                       ` dMMMMMMMMM{                                           `          `                               ,MMMMMMM    //
//    MMMMMMMM,       `  `  `  `                              `   `           `        `            .MMMMMMMMMMb                              `      `             `     `    `  `  `  `  `  `  `  `  JMMMMMMM    //
//    MMMMMMMMMNggggggggggggc     `               `                     `             .&&&&&&&&&&ggMMMMMMMMMMMMMMNgg&&&&&&&&&x                                                          gggggggggggggMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMM@            `  `  .]     `    `        ,,            `     WMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM^    `  `  `  `    g  `    `   `  `     h     `            ,MMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMM#          `       .M]              `    ,N,     `            MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM$                  J#                 `  Mb                  JMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMM`                 .MM]       `           ,MN.       `    `    .MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF                  .M#                    MMp      `  `  `     vMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMM'    `  `         .MMM]   `      `     `  ,MMN                  ,MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMF       `          .MM#    `  `  `         MMMx `                UMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMM%           `   `  dMMM]                   ,MMMb  `      `        ,MMMMMMMMMMMMMMMMMMMMMMMMMMMMMM@            `  `  .MMM#             `  `   MMMM,             `    WMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMD   `              (MMMM]      `      `     ,MMMMb    `             JMMMMMMMMMMMMMMMMMMMMMMMMMMMM#                                                                                         //
//                                                                                                                                                                                                                //
//                                                                                                                                                                                                                //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract HSG is ERC1155Creator {
    constructor() ERC1155Creator("HAKUMAI Special GOHAN", "HSG") {}
}

