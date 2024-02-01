
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: lucha
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                            //
//                                                                                                            //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWWNXXKKK0000000KKKXNNWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMN0KMMMMMMMMMMMMMMMMMMMMWNXK0OkxdooolllllllllllooddxkO0XNWWMMMMMMMMMMMMMMMMMMMN0KMMMMMMMMM    //
//    MMMMMMMMMMMO;oWMMMMMMMMMMMMMMMWNKOkdollllllllllllllllllllllllllllodxO0XWMMMMMMMMMMMMMMMM0;lNMMMMMMMM    //
//    MMMMMMMMMMXc '0MMMMMMMMMMMWWX0kdolllllllllllllllloxkxllllllllllllllllloxOKNWMMMMMMMMMMMNl .kMMMMMMMM    //
//    MMMMMMMMMWx.  cXMMMMMMMMWN0xollllllllllllllllllld0NNXkllllllllllllllllllloxOXWMMMMMMMMWk.  :XMMMMMMM    //
//    MMMMMMMMMK;   .oNMMMMMWXOdllllllllllllllllllllldKWWMWXkollllllllllllllllllllox0NWMMMMWO,   .xWMMMMMM    //
//    MMMMMMMMWd.    .lXMMWKkolllllllllllllllldxkO00KXWMMMMMNK00OOkxlllllllllllllllllx0NWMWO,     ;KMMMMMM    //
//    MMMMMMMM0,       :OXkollllllllllllllllllokKNWMMMMMMMMMMMMMWXOdlllllllllllllllllllx0Kd.      .dWMMMMM    //
//    MMMMMMMWo.        .;:cllllllllllllllllllllokKWMMMMMMMMMMWXOdlllllllllllllllllllllc:'         ,0MMMMM    //
//    MMMMMMM0,            .;clllllllllllllllllllldKMMMMMMMMMMNkllllllllllllllllllllc:,.           .oWMMMM    //
//    MMMMMMWd.              .',:cllllllllllllllllxXMMWWWWWWMMWOollllllllllllllllc;'.               ;KMMMM    //
//    MMMMMMX:                   ..,;:clllllllllllONXKOxddxk0XNKdlllllllllllc:;'..                  .kMMMM    //
//    MMMMMMO'                       ...,;cclllllldxdllllllllodxollllllc:;'..                        lNMMM    //
//    MMMMMWx.                            ..,;clllllllllllllllllllll:;..                             :XMMM    //
//    MMMMMWd.                                .,:llllllllllllllllc;..                                ,KMMM    //
//    MMMMMNo                                   .,:llllllllllllc;.                                   ,0MMM    //
//    MMMMMWo                ...                  .;clllllllllc'                   ..                ,0MMM    //
//    MMMMMWd.               c0Odc,.               .;clllllll:.               .':okKx.               ;XMMM    //
//    MMMMMMk.               lNWNK0kxoc,.           .;llllllc'            ':ldkOKXNWO'               cNMMM    //
//    MMMMMMK;               lXXOdl;,,:odo,          .cllllc,.         .cddc;,;:ok0NO'              .xWMMM    //
//    MMMMMMWd.              ;KMMWN0;   .lk:         .;llll:.         .dx,.  .dXWWMWd.              ,KMMMM    //
//    MMMMMMMK;              .lXWMMX: .,..:o'         .clll;.        .lo..'' .kWMMWO'              .xWMMMM    //
//    MMMMMMMWO,               ;xXWW0ocloxddc         .:llc'         'ddxdlcckNMN0l.              .oNMMMMM    //
//    MMMMMMMMWO,                ':dkKXNWWWNd.        .;llc.         :KNWWNXKOxl;.               .oNMMMMMM    //
//    MMMMMMMMMWKl.                  ..,;:cc,          ,llc.         .:c:;,'..                  ,kNMMMMMMM    //
//    MMMMMMMMMMMNO:.                                  ,ll:.                                  'dXWMMMMMMMM    //
//    MMMMMMMMMMMMMXo'.                                ,ll:.                               ..;kWMMMMMMMMMM    //
//    MMMMMMMMMMMMMNklc.                               ,ll:.                              .;cdKMMMMMMMMMMM    //
//    MMMMMMMMMMMMMW0oc,                              .;llc.                              .:lkNMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMXxl,       '.    .''''.........''';cllc:,'''........''','.   .'.      .:oOWMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMWOl;.     .;,   .:llllllllllllllllllllllllllllllllllllllc'   .;'      'cdXMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMWKdc.     .:;.  .:lllllllllldkO0000KKKKK000Okxolllllllllc,   'c,     .;lOWMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMNkl;.    .:c,. .:llllllllloONWWMMMMMMMMMMWWWKxlllllllllc'  .:c'     .cdKWMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMWXdc'    .;lc;..,cllllllllloxkOO00000000OOkkdolllllllll:..':lc.    .;oOWMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMW0o:.    'cllc;:clllllcc::;;,,,,,,,,,,,,,,;;::ccllllll:;:lll;.   .,lxXMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMNkl:.   .;lllllllc;,....                     ...';:cllllllc'   .,cdKWMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMWXxlc'.  .cllll:'.            .........            .,cllll;.  .;co0WMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMWXxlc:'..,cll;.    .,:loxkOO00KKKKKK000Okxdoc;.     'cll:...;cloOWMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMWXxllc:,,:lc'    :0NWMMMMMMMMMMMMMMMMMMMMMMWWXd.   .;lc;,;cllo0NMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMWXkollllllc'    lNMMMMMMMMMMMMMMMMMMMMMMMMMMWO.   .:llllllld0WMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMWNOollllll;.   .:kKNWMMMMMMMMMMMMMMMMMMWNXOo'    'cllllllxXWMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMWKxlllllc;.     .';:cloodddddddddoolc:,..     ':llllldONMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMNOdlllll:,..                             .';cllllokXWMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMWXOdlllllc:;,'.....            ......',:cllllloxKWMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMWX0xollllllllcccc:::::::::::::cccllllllllldkKWMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWWX0kdollllllllllllllllllllllllllllloxOKNWMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWNX0Okxdolllllllllllllllloodxk0KNWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWWNXK00OkkxxxxkkOO0KXXNWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//    MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWWWWWWWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM    //
//                                                                                                            //
//                                                                                                            //
//                                                                                                            //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract lucha is ERC721Creator {
    constructor() ERC721Creator("lucha", "lucha") {}
}

