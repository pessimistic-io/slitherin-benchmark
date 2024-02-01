
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Hateland Inc.
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                            //
//                                                                                                            //
//                                                                                                            //
//                                               ............                                                 //
//                                     ..,:cccccllooooooolllccccclc:;'..                                      //
//                                .,:ccclc:;'...               ...,;ccccccc,.                                 //
//                             'cllc,.                                  ..;lool;.                             //
//                          'lol;.                                           .;lddl'                          //
//                       .:do;.                                                  'cddl'                       //
//                     .cxl'                                                        .cxxc.                    //
//                    :xo.                                                             ,dko'                  //
//                  .dx,                                                                 .oOd.                //
//                 .xx.                                                                    .dOl.              //
//                 c0,                                                                       ,xk'             //
//                 ok.                                                                        .oO;            //
//                 dx......      ..........                                                     l0;           //
//                .c:;;,';loccclooddddoooooll:.                                                 .dO'          //
//                ,:.',''lkdoooollllllllllllod,                                                  'Oo          //
//                ':;;,''oxoooooooooooooooolox;                                                   lO'         //
//                 ld'',:dxlooooooooooooooolokd:ccc:;'.                                           ;0:         //
//                .kx..;lkdoooollllloooooooldOo',;:cllc:::,.                                      ,0c         //
//               'xd,',:oxxxxxkxxxxxxxdddddoxKl.          .                                       ;0:         //
//              ,xolONWNOooddddddddddddddddd0WX0Oxol:'.                                           l0'         //
//             'kloWMWKkolooooooooooooooooxKWMMMMMMMMWXOxo;.              'clc,.                 .kd          //
//             lk;kMWX0OkkkkkkxxxxddddddxONMMMMMMMMMMMMMMMWKd,          .od,                     ;0c          //
//             lk,xMMMMMMMMWWWNXXXNNNNNNWMMMMMMMMMMMMMMMMMMMMNx'       .ko.                      ok.          //
//             :O:oMMMMMMMMMM0:,,,;coOWMMMMMMMMMMMMMMMMMMMMMMMMK:     .dd.                      ,O:           //
//             .OolWMMMMMMMMWd''''''.:KMMMMMMMMMMMMMMMMMMMMMMMMMX:    ;O,                       oo            //
//              dxlXMMMMMMMMO,.,'',,',OMMMMMMMMMMMMMMMMMMMMMMMMMMx.   oo                       :x'            //
//              lOc0MMMMMMMX;  ;oxo,. lWMMMMMMMMMMMMMMMMMMMMMMMMMd   .o;                      .xc             //
//              cO:xMMMMMMNl .lXNNWO' .OMMMMMMMMMMMMMMMMMMMMMMMMK,   'c.                      ox.             //
//              cO,:XMMMMNo. oNXKWMMk. lNMMMMMMMMMMMMMMMMMMMMMWO,    ',                      ,O:              //
//              cO' .:lol,  cXXKWMMMWO:,lKWMMMMMMMMMMMMMMMMMNkc.      .                      dx.              //
//              lx.    ..  '0NKNMMMMMNc  .cx0XWMMMMMMWNK0Oxc'        .'.                    ,O:               //
//              od    .o,  lWNXMMMMMMMx.    ..';:cc:;,...              ..                  .xx.               //
//              :k;   ck. .xMWNXXWMMMMx.                                                   ok.                //
//               ,dxloKk.  .c;'..;okko'                                                  .ok'                 //
//                 ;kNMO.                                     ..';:cldxkkkxc:cl.        .dx.                  //
//                   ,OK,                             .',;loxO0Kd:;,cKWNXO;  ,k;      .lkl.                   //
//                    oX:                          'cd0NWMMMMMMk.    'lo:.  'OKc...':oxl.                     //
//                    cNl                 ..     .cl:OMMMMMMMMX:           ,0NXKkollc,.                       //
//                    ;Xo                 .;.    ...lXMMMMMMMWo           ,ko'...                             //
//                    .kk.                .o: ..,cd0WMMMMMMMWk.          'ko                                  //
//                     ,xxdddllc:;;;;;::cldXXO0XWMMMMMMMMMMWO.          .xo.                                  //
//                      .:kxclOWMMMMMMMMMMMMMMMMMMMMMMMMMMXd.          .dd.                                   //
//                      cd;.,xNMMMMMMMMMMMMMWWXK0kocoXWKOd'            lx.                                    //
//                     .xo..,:ccllllllkWMMMO:'...  .':,. .....        ;k;                                     //
//                      dk;,;:;;,,''..cKNXKo.  ..       .',.',.    .,co,                                      //
//                      ld  ...'''''........             .,.';c:::::;.                                        //
//                      :k'                            ..,lolcc;'.                                            //
//                      .xo.                     ..;cc::c:,..                                                 //
//                       .clllc:,'''....'',;::cc:cc:,.                                                        //
//                          .',;::ccccclccc:;,..                                                              //
//                                                                                                            //
//                                                                                                            //
//                                                                                                            //
//                                                                                                            //
//                                                                                                            //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract HATELND is ERC1155Creator {
    constructor() ERC1155Creator("Hateland Inc.", "HATELND") {}
}

