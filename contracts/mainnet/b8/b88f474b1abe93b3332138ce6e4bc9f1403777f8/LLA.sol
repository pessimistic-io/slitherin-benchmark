
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: LELE'S LIFETIME AIRDROP
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                              //
//                                                                                                                                                              //
//        ....                                                                                                                                        ..        //
//       .                                                                                                                                              .       //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                           ..  .. ...   ..... ...................  ................................   ......................                  ..      //
//      ..                        'lxlokkkko:cdkkdldkkkxl:lxkddkkl:ccdkdxxdoxxxxxxxxxxxxxxxddxxxxxxxxxxxxxkkxookOkxxxkkkxxxkkxxkkdk0Oo'                 ..      //
//      ..                      'oOkcoKMMXd:o0NNkcdNMW0l:xXWMNNX0o,lO0KOkO0K0OOOOOOOOO0KOxOKkl:oOK0dc:coOK0kk0XKOOOkOKNN0kKXOxxOO0Kk:..,.               ..      //
//      ..                    'oOKXOxkXMWOokNNXKkxOXMWOoOWMX0NWKkddk0OkO0KK000000000KKkl'.kx.  ,OO:. .ck0kk0KKOxk0KXNXKO0XXX0kOKKk;..;Ok.               ..      //
//      ..                  .:oxxdkOkxkOkxxOOddkOkxkOOkxkOOxdkOOxdxxddxOOkkkkkkkkkkO0x:'',dd,,cxx;'':dkddk00kxxddxkkkkxdxxddxk0x;..:dkKO.               ..      //
//      ..                .:odoooooollllllcccc,................................................................................,cdkOxoOO.               ..      //
//      ..                ,O0O00KKKKKKKK000Oxd;      .        .        .'       .''.        .''.      .               ..       l0kdxkx0O.               ..      //
//      ..                ,xO00KNXNNKXWKXWKK0o'     ,l.      .l,      ,o;       :kl.       .cOx'     .:'  . .'.';    .l:.     .lkxoxkd0O.               ..      //
//      ..                ,kkOO0K0KKO00kOKOOOd'     ;o.      .o,      ,l'       :x;         .o;      .c'    .dkOo    'c.      .lOxxOkoOO.               ..      //
//      ..                ,O0OOOOOOOOOOOOOOO0O,     ;o.      .o,      ,o;.      :xo.        .o;      .c'    .lcd:    .l:.      lOxk0kd0O.               ..      //
//      ..                ,OK000KK00KKKKKKKKKO;..   ;o.      .o,      ;l.       :d'         .l;      .c'    ':.;;    ':.       lOk00kkKO.               ..      //
//      ..                ,OKKKKKKKKKK0000kkOO;     ,xc.     .l'      ,c.       cOl.        .c,      .:.    ':.;,    'o;       lkk0KOkKO.               ..      //
//      ..                ,OdcdO0KKKK0OkkOxdkO:      .,:;.    .        .        .''.         .               . .      ..       lkdk0kd0O.               ..      //
//      ..                ,O:  .o0K0o,...'cx00;       'lod,        ..         ..        ..      .                ''..     ..   lkdOKkdOO.               ..      //
//      ..                ,k:   c00c       .x0old'    .,:l.        '.  ..',:ldxkxd,   'lxdl;   .....    ,,      ;O0kkdlc.      lOxOKOkKO.               ..      //
//      ..                ,Oc   c0d. .::.   ;OkkO,    .,;,;.    ..',:ldk0Okdol:c0Nc  .xx:;dk' .cxO0x.   ,o'    .odlolldkc.    .lOkO0OkKk.               ..      //
//      ..                ,Oo.  .:. .dK0o.  'kOkx,   .,.  ;l;;cok000kdoccloodkc;ONl   ;llxl,  'dOOOx.    lo.   ;kdxOdlxx;';:,..ckOkkkdOO.               ..      //
//      ..                'OO:      :0K0k,  'kOkd' .;'.;lok0KOkdol:,.';lx0WMMWd:OXo.,'. ..    'd00Od.    'x;   .:coxookc .cl:. ckOO0OxKO.               ..      //
//      ..                ,kkol;..'cOK00k,  'kl..  ;, 'xk00ooddl,':cl:'.':kNMMxcO0: .:o;'''.  .';,'.      lk'     .c;...  ,:.  lkxkOOxKk.               ..      //
//      ..                ,kl..;dO00KKK0k;  'k:    ;, ,kkKd:0Wk;;xKXXKOd.  ;0WklO0;.:c;o:..,,'   ..   .   .l,      .;'.      ..lxdxOOkKk.               ..      //
//      ..                ,kxcccxK00KK0K0kd:lk:    .,,:kk0ocXx..dXXXNWNNx.  ;KkoOk;.:c;:.    ';''oOd'..''        ..  .',.   ''.l0k0NOd0k.               ..      //
//      ..                ,k; .,d0KKKKK00KK000:  ..  .lOk0llO, 'xXWWWWNNX;  .kkdOx,  ..    .;:lxOxdO0x;.'.  ,;..        ,'  .'.l00KKko0O.               ..      //
//      ..                ,k;   c0KK0KKKklok00; :xkd. :OO0clk. .:0MMMMNXK;  '0kdOd, ..     'oxOx:..';c,  .ckO00Okxdolc:;:c'.  .lOk0XOkKO.               ..      //
//      ..                ,k;   c0kdk00Kd. .cO; ;ddl. :0OO:l0;  .xWWMMWKl..ckKxxOo' .,:d:   'dX0'        :XXk:;coxOKXNNNXKOxl. lOk0Xko0O.               ..      //
//      ..                ,k;   :0o..;xKd.  'k:       c0OO:cKkldd0WXXKkl. .kKKdxOl..:x0KOd:. 'ol.   ..  .xXO:   .';:;;co0WN0d. l0O0KOx0O.               ..      //
//      ..                'k;   .;,  .dKd.  'ko,''.,,,dK0k;oNKkOKKNNNK00o;cdddoOx;. ,dkkxdl.     .:,'l; ;KXd. .l0XNXk,  lK0Oc  lOxOXOkKO.               ..      //
//      ..                'kc         ,o:   'ko,;;,'..o00x,oX0xkK0KKkdlccoddodxc.    .,'.        .oc,l,.dN0c  ;0KKKKNd.'k0Ox'  l0OKXOkKO.               ..      //
//      ..                'k0xl;'.          'ko.      oK0x,oWX0kdc;ccloxdlcc''c'   ..  ......     .,'. ,0XO,  oXNMNOk; lX0ko.  lOxOKkd0O.               ..      //
//      ..                'kK0KK0ko:,.      'kl;,     o0Od',c:cccllll;ckd;;::cd,   .  ,xOkkkxdlc;,,;,;:kXXx..'oO0Kk:. .xKkxl,'.lkxOXklOO.               ..      //
//      ..                'kKKKKKKKK0Odc;.. 'k:.:.   .o0Okcclllc;'.....,::::::,       c0OkOKK0Ox:.    ,0K0xlx0K0OOOo,.;xkOo.   lOkO0koOO.               ..      //
//      ..                'kKKK0KKKKKK0Kk:;;oOc;:  ...,lllc,.    ;dxdc.        ';,,' .lk:,odokkd'  .. .oO0KXKKKKKKK00OO00k:    lOk0NKKWO.               ..      //
//      ..                'k0000KKKKK00Kd. .:Oo,. ,xOl    ...    cOkko.   .    :OkOx..xKOO0O00kl. .cl....,:lOkodxkkO0KXXOl'..  l0OKkdk0k.               ..      //
//      ..                'xl;cdk000KK0Ko.  ,k:   .;c'    ,occ'   ':;.  ;ool.   ......,odlllool'     .:,  .co'  .,,.:xc'.:xOk:.lKKOol;ok.               ..      //
//      ..                'x;   .,:oxO0Ko.  'kc.,,,,....  ':',.         .oc;::.   ,c;,,;.         .','.   ;d;...,:,  ;l..:kOx;.lK0XWKOXk.               ..      //
//      ..                'xc.      ..;l:   'ko','',,lO0d;.     ,c;:;. .ccl;...   ,c;cl.      .':okKNO,';:c.  '.      '::::;'..lK0XWNNWk.               ..      //
//      ..                'k0xo:'.          'k:      .,lkO:    .x00Ok, .'..  .loc:,'.,,    .cdOOdllo0Xo;'    'colc:'    .;;;:;'l0kkOdxNO.               ..      //
//      ..                'xo:ok0kdc,.      'ko;;:::;.  ..  .. ,k00Ox'  ..  .oNXKK0xol,    ;x00;   .lKd.     ',',;;.   .....''.lOl:xl:Ok.               ..      //
//      ..                'x;  .oKKK0Oxl;.. 'ko;;:;,c'     :kd' .:xKx.  ..  ;0NNXXX0KKOd:' .lOx:;cx0KX0' ...''       'cdxkOOOOloKklxOkKk.               ..      //
//      ..                'x;   cKKKK0KKx,''cO:.oxx:;'     .ok:   .;;.      oNNN0xKN0KXXK0xloxOKO0XXXNK; ....'. .' ..,dxoxdclo;o0KXXNXNO.               ..      //
//      ..                'x;   cKxclk0Kd.  ;k:,xxxc:'   ',. .',,..      ..;kWNKKXNx..:d0XXXKOO00Oxo::l'      .'xKo. .ddcl,'x0olOK0dkOKO.               ..      //
//      ..                'x;   ;Oo. 'xKo.  ,kc:xkkdo,  .od'    .,,,;,,;;;cxKKkokK0:;dc,,;oOKK0OOd;.  ,,   ... .c0x. 'xdll,cXNdo0Oc,olcd'               ..      //
//      ..                'x;    ..  .dKo.  ,ko:c:;;::.     .:llc:.       'OWNx;lx:;O0oco,.l0XNX0Ok:  :, .cl,cl. ',  'kdlo:cO0oo0xcol,ok.               ..      //
//      ..                'xo..       .:,   'k:    .l0x'  .o0NNXK0O; ,:.  :K0OKNOc;oXkl,:;:O0OkkkOx,.;,  .cc,lo.     ,kdlO00K0loKNN0kxKO.               ..      //
//      ..                'x0Oxo:'.         'k:    .::,. .lO0XXK0Ok:.':.  l0Ok0Xc.c0KXKl.,xKx...:kl'..     .,,'.     ;Oxd0XXXXooKNWNXxkk.               ..      //
//      ..                .xKKK0K0kdc,.     'k:   .:,    .lO000Od:.  .   'OX00Nx..cO0KOo,oKNx.;k0d.'c'  .;cldkOk:    .:lllxklc,lKXKOx,ck'               ..      //
//      ..                .xKK0KKK0KK0Oxc,..,kl...;l;',,'  ;xxl,.  ,:.    ;d0XNo  .:odd,c0XWx..d0;.oXx..lKK000KXO'        ;d,  l0kdxO:ck.               ..      //
//      ..                .x0KKKKK0KKK0Kd'.'cOc...:l'..',:,...    .:c. .';ccdKXKxll;...,xXWWKddOx. .'.  'x0KXXNNKl  ..     ;do'l0k0oo;ck.               ..      //
//      ..                .xkx0000KKKK0Ko.  ,k:   ':.   .lddd;  ..  .:okOOxc'..;dO0Oc..o0NWK00KO:,,'     :OKXKKXXd.          ,,oOkOdd;ck'               ..      //
//      ..                'd:.';ldO0000Ko.  'kxlc;:l,   ;dddo'    'odk00XNNd.     .ckOk0NWKO000l  .;:.   .dOkdl:,.  'lxxo;.    l0kkxx;ck.               ..      //
//      ..                'd;     .,cox0o.  ,kxdO0K0kdlc::;l:    ;d:.oWKKNNd.    .   ,d0NWXK00k;....;;    ...     .ckXNWNKc.   l0Okxxcok.               ..      //
//      ..                .dd;..      .'.   'kdlllccloxO00OOxc;,cx,  .lccoo,..cxkkxl'  .;xXWKkc.''''co;.     .c;  ,kXMXXMNk'   l0kxdkkOl.               ..      //
//      ..                .x00Oxo:'.        'k0XNX0kocclc;oxdxOOOkoc;'.     ,kXXXXXX0c   ,dlc,.     'xOl.    .ol. :kNMXXMWk'   lKxxOOx;                 ..      //
//      ..                .x0000K00kdc,.    'kOKWWMMWKOXd.:c .;kxcoOOko.   .cKX00KKXN0;  ;d.         ':.      .'  'dKWNNWKl.   oXO0k:.                  ..      //
//      ..                .x00000000000Odl;':k0NWXXXX0OXo :o,;dd. .OK0x.    ;kKKXXXNKd.  .cl'.  ,oddolc:;,'..;c;.  'lk00x:,;lo:oOl,                     ..      //
//      ..                .dkOO0000000000KK00OO0KKXNXXKXo .:lo:.. 'OXKx.     ,cllcc;.   .. ':;,,dK000KK0kOx;...':;'. ...,lkKXXo..                       ..      //
//      ..                .',,,,;;;;;;;;::::::;cllllllcc' .;;;;;,..:cc,                         .clccclc;;,.  .'..'.    'ccccc.                         ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//      ..                                                                                                                                              ..      //
//       ..  .                                                                                                                                         ..       //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract LLA is ERC1155Creator {
    constructor() ERC1155Creator("LELE'S LIFETIME AIRDROP", "LLA") {}
}

