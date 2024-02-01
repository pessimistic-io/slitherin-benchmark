
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: DEVA By Ramanand
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                         .,.                                                                                                  //
//                                                        .dxc;'                                    .,oc.                                                       //
//                                                        cd:..,;,.                              .,lxkkk:                                                       //
//                                                       ;l;:,   .,;,.                        .,lxOkoclcc'                                                      //
//                                                      ,l'.,;.     .,,'.                  .;ok0Okd:';l',c.                                                     //
//                                                     'o:...;'        .,,'.            .:oO00Okxo,..;c. ::                                                     //
//                                                    .oc....';.          .,'..     .':dkO000Oxo:'...:c. .:'                                                    //
//                                                   .lc'.....;.            .';;:;:lxO00OO00xdo;.....:l.  .:.                                                   //
//                                                  .ll.......,'              'd000OOO0000kxdc'......:c.   ',                                                   //
//                                                 .cl''.......;.          .;ok0OOOOOOO00kdl;........:c.    ;'                                                  //
//                                                 :l'.........''       .;okOOOO00000OOOkoc,'''......::.    .:.                                                 //
//                                                ;l,....... ..''.   .;ok00OOOOOO00000kdo;'''........;;.     ':.         ..........',.                          //
//                                             ..:o:,'......  ..';,cdO00OOO000000000Oxdc,''''...'....,;.     .ll,,,,'''',,,,,,,,,,,cko.                         //
//                    .clc:;,,'''.'''''.......',:c,.............'oxk0000OOOO00000K0kdo:,,'.''..'.....;:.      ..                  .:l,                          //
//                    .dKOxolc;'.                                .:lO000OO00OO00kodo:,'''..','''.....::.       ..               .;;,:.                          //
//                     ;OOdc;;:c:,'..                             ':o000OO0000Oxoll:'.'''..'.....'..'::.        .              ,c:';;.                          //
//                     .l0Oxl;''''';;,,'...                       .,cx000OOO0Odol:,''...'''.'.......,c;          .           .;:,,,c,                           //
//                      ,O0Oxl,..'''.............                  .:o00000Okdl:,,,'''..''..'.....''cx:          ..        .;:;,,',;.                           //
//                      .d00Oko:'........    ...''''...             'lk0000ko:'.''''.'''............;x;           ..     .,c;''''',,                            //
//                       :O000kxl,..'...... .... ...'...''...       .;o00kxo;'',,,,'..''............,d;           ..    ':;,,''''';'                            //
//                       'k0000Oxo;'.................    ...'''',..  ,:colc,''''','.''''''.''.'..''.'o;            .. .cc,''''','';.                            //
//                       .lOOO00Oxo:................  .     .. ..'',;ldl:'...',''''.'....'.'.'''.....c,            .:dd:.','..',',,.                            //
//                        'k000000ko:'..''................'''.......'l0k:,;;;,'....',,,'............'c,          ...';::;'.',,'..;'                             //
//                        .d0000000kllc,................''''''.....'::dd. ..',;;::;,'....''.''.......:,       ....     .,;:;''''';.                             //
//                        .dK0000000Oxol,..............,,'''''....;c;':x;       ...',,,;;;'...'''....c,     ...           ':c:,'::.                             //
//                    .',;:lk0OO0OOO00kl:,....'......',''''''....:c,',,ol.             ..,,,;;;,,'.''c;  ....               .;clo;                              //
//                ..,,::,'..cO0OO0OO000klc:'.......',,'''''....,c:,,,,'lx,                   ..,,,,;;ol...                     ,ol.                             //
//             .';;;,..'....;k00000OO000Oo:c;.....,,'..'''....:c;,,;,,;cd:                         .;kk:,,'..                    .,,'                           //
//         .',;:;,'...',....'cO0000OOO0000d:c:'.'''..'''....'c:'',,,;;;;ll.                        .lkl,.,:;;;;,,..                 .,'.                        //
//        ;kx:',,''...','..'',d0OOOOOOO0000kc:c;'..'''.....;:,',;;,;::::lo'                       .codc'..,'..',;cc:;;,'..            .,,'                      //
//         ,dOkdoc;'...','..''cO0OOO000000000dcc;.'''....,c;',;;;;:;::cl:l:                      ,olcoc...''.',..,,',::cc:;,,'.         .';,.                   //
//          .:k00Okdoc;',,  .':x000OOOOOO0000Kklc:,.....:c'.,::,;;;;cllc;cl.                   .;lcccdc..''..',.',,';;,,,'',:lo:;;'..      .,,'                 //
//            .lO00000Oxdl;....lO0OOOOOOO000000Ooc:'..':;..,::,;c;:cll::::o;                  .:;;c:cdl..'''.''..,,,;;,,,,',,;:,;lolc;,,'.   .,:,.              //
//              ,x00OO00000Odl:ck0000000000000000kdocc:'.';::;::,:llccc:;;oc.                ,:,',c:cdl..','.''..,,,;,,,,,'',;;,,;:c;,,:llc;;,',::;.            //
//               .ckOOO00000000kk0Oddxdddddxxxkkkkk0K0o:;;::::,,:lc::c:,;cll.              .:c'..,::cdc..'''.''..',,;;,,,,,,,,,,;;;:;,,;;:;:c:cc::ldl;.         //
//                 'dO000000O0OdkK0OOOOkOOOOOO00OkO00OO0kdol;.;lllc:;;;:cl:l,             .cc'...,:;co:'.','.''..'',;;,,','''',,,;,;;'',,;,,;;;;::clxOl.        //
//                  .:k0000O00do0K0000000K0000Okxdk00OxxO00kccoolc;,,:ccc:;cc.           'lc,''..,:;lo;'.''..''..',,;,'''''''',,,,,;,'',;:cc:ccloooo:'          //
//                    .oO0000klkK000K000KKKK0kxxloO0O0Oxdk000Okdc,';::cc:;;;c'          ;ol;,'...,:;co;''''..''..',,;,''''...',;,,;:::::cloooodxdc'             //
//                      ;x00Olo0K00K00KKKKK0xxd;:k0OO000xoxOOkOOkol::cc::;''c;        .ll:;,''...,;,cl,''''.'''..''';;'''''.';ccclldxkxxxkO00ko;.               //
//                       .lOxlOK000KKK0KKKkddc',d0OOOO000kodOOO0000kdl::;,,':c.      'ol;,,''....',,cl,'..'..,'..',';:;;::cldxxxxkkO000OO0Ox:.                  //
//                         ,oOK00000KK0K0xoo;..;k0OOOOO000OxdkOOOOO00Oxl;,'.,c'     ;dc,,,'''....',':c,''...',,,,:ccldxxxxkO000000OO000Okl,.                    //
//                          c00000000KKkddc'...oOOOOkOOOOO00koxOOkkkOOOOxl;'':;   .cdc;',,'.....',,':l,';:::clldxxxxkO0000O00000OOO000x:.                       //
//                         .xK000000K0xlc;'...cO0OOkkkOOOOOO0OdokOOOOOOOOOkdclo'':oo:;;,;::::::cclodkOdclddxxkO00000O0000000OO00OOkdox;                         //
//                         l000000KK0dl;.....,x00OOOkkOOOOOOOOOdlxOkOOOOOOOOOO0O0K0OxxkkkkkOO0OkxxxkKOodkOOOO00000000000000OOO0Oxl;'.:l'                        //
//                        ,O00000K0kdo:......o0OOkkkkkkkkOOkkkO0kodkOkOOO0OkxO0KKKK0000OkxollodddkOdoc. 'lk000000000000000000xoc,.....:o'                       //
//                       .dK00000Odoc'......;O0OkkkkOOkkkkkOOkOO0OooOOO0OkkkO00000OxdoooooodxO00Od;.,:.   .;oO0000K0000000Od:'.........:o,                      //
//                       c0K0000kol:........o00OOOOOOOkkkkkOOOOOO00xdk00OkkkxddxxddddxO000OO000k:...;:.      'ck0000000Odc,.............;o,                     //
//                      'kK0KKOdlc;'.......c0K0000000000000000000OO0kk0OlldxxkO00000000000000Ol,... ';.        .;dOO0ko:'................;l,                    //
//                     .l0000Odo:'........'dK00000OOOOOOOOkxddxxxxkOkk0Oock000000000O000000Od,......';.           ,xOoldol::,''............:,                   //
//                     ;OKK0xdo:''...''...l000OO000OkxxdoddddxkkOOOkxOO00dok00000000000000x:'.......;;.           .oooO0KKK0OOkdolc;,;,'''..:,                  //
//                    .dKKkool,..'''''''':OK0OkddoddddxxkOOOOkkkOOkxkOOO00kookOOOOO00000kc........',:;           .odxO000000KKKKKKKKK0kxxxdlldc.                //
//                    c00xll:,'...',,;,',cdddddooxkO000O00OOOOOOOOdxOOOOOOOOdlx0OOOO00Oo'...........;,          .ldxOO00000KKKKKKKKKK0Okkdolc:,                 //
//                   ;OOdol;..',,,,;:clloodkO0000OOOOOOO00OOOOOOOddO0OOOOOO00kox00000x:'..........  ,,          :dk0O000000000Okdol:;,...                       //
//                  'k0xol;,;;:looddxkO0OOkOOOO00OOOOOOOOOOOOOOOdlk0OkkkOOOOOOkollxOl,..........    ',         ;ox00OOkdoc:;,...                                //
//                 .lKK0kxxxkkO000OOOOOOOOOkOO0000OOO00OOOOOOO0dcx0OOkkOOO0OOOOOdlc:'...............,'        'ddcc;'..                                         //
//                  .,,;;;;;;;:ccclloodxkkkkOKKK00000000OOOO00Odx0OOOOOOOOOOOOOOO0Oo'.............  ',       .cc.                                               //
//                                      ....:OKOkkkkkkkkkkkO0000K00OOOOOOOOOOOO0000Ox;.........     .,       ;:                                                 //
//                                           c00O00OOOOOOkkO0xdO0xdk00OOkkOO00OOOOOOOk:. ....  .  ..,,      ':.                                                 //
//                                           .x0O000000000OOxdO00OdoodkOOOOO0OOOOOOOOOkc........ ...:,     .:.                                                  //
//                                            c00000000000Odx0000000Odoook00OOkOO000OOOOd;.. ... ...;,    .:,                                                   //
//                                            'k000000OO0Oxk00000000000kdoox000OO000OOkkOkc.... ....,'    ;;                                                    //
//                                             c0K0K0000kdOK0000000000000ko::clk00OOkOkOOOOd'.. .. .;'   ,:                                                     //
//                                             .x000000xdOKKK0000000Oxl:'.     .;cokOOOOOOO0kc......;'  ':.                                                     //
//                                              :0K0KOdx0KKKKKK0koc,.              .;oO0OOOOOOo. ...,' .:.                                                      //
//                                              .d00Odk0KK0Odl;'.                     .:dO00000x:...:'.c'                                                       //
//                                               :OkdOOko:,.                             .;oO0OOkc..;,;;                                                        //
//                                               .ldl:..                                    .;ok0Ol,co;                                                         //
//                                                 .                                           .;okkOo.                                                         //
//                                                                                                .:c.                                                          //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract DEVA is ERC721Creator {
    constructor() ERC721Creator("DEVA By Ramanand", "DEVA") {}
}

