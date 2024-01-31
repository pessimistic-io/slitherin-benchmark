// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: godaydream editions
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                              //
//                                                                                                                                                              //
//    ooxdcclllodlllcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc::::cc:::::::::::::::::::::::::::::::::oxoododo.    //
//    dxkdlclllodollccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc:::cccc::c::::::::::::::::::::::::ccccc:lxocldko.    //
//    ldxolclllodolllcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc:ccccccccccc:::::::::::::::ccccccccccccccllc:col.    //
//    loollllllodolllccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc::::::::::ccccccccccccccclooooool.    //
//    xxxdllooodxdoolllcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc:::c::::ccccc::::;;;::cclddooool.    //
//    llloc;xxxxxxxxxxclcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc:.xxxxxxxxxxxx.:lcccccc.    //
//    llocxxxxxxxxxxxx.xlccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc:.xxxxxxxxxxxx.:lcccccc.    //
//    llo:xxxxxxxxxxxxllcccccccccccccllllll                          _                 _                                 ccccccccccc:.xxxxxxxxxxxx.:lcccccc.    //
//    lll;xxxxxxxxxxxx ;llccccccccccccccccc                         | |               | |                                ccccccccccc:.xxxxxxxxxxxx.:lcccccc.    //
//    lloclllxxx...l;;;ccclllllllllllllllll           __ _  ___   __| | __ _ _   _  __| |_ __ ___  __ _ _ __ ___         ccccccccccc:.xxxxxxxxxxxx.:lcccccc.    //
//    llo;;xxxxxcccccclllllllllllllllllllll          / _` |/ _ \ / _` |/ _` | | | |/ _` | '__/ _ \/ _` | '_ ` _ \        ccccccccccc:.xxxxxxxxxxxx.:lcccccc.    //
//    dddxxxxxxxkxxxxdddcccclllllllllllllll         | (_| | (_) | (_| | (_| | |_| | (_| | | |  __/ (_| | | | | | |       ccccccccccc:.xxxxxxxxxxxx.:lcccccc.    //
//    dddxxxxxxxkxxxxdddoocclllllllllllllll          \__, |\___/_\__,_|\__,_|\__, |\__,_|_|  \___|\__,_|_| |_| |_|       ccccccccccc:.xxxxxxxxxxxx.:lcccccc.    //
//    loollllllodolllccllllllllllllllllllll           __/ |    | (_) | (_)    __/ |                                      cccclllooooooooodddkkkkkxxxxxcccdd;    //
//    cccc.             lllldddflllllllllll          |___/_   _| |_| |_ _  __|___/__  ___                                ccccccccccccc:          cdxxxxxxxx;    //
//    ccc;;             lllldddflllllllllll            / _ \/ _` | | __| |/ _ \| '_ \/ __|                               ccccccccccccc:           ccccccxxx;    //
//    ccccc             lllldddflllllllllll           |  __/ (_| | | |_| | (_) | | | \__ \                               ccccccccccccc,           ccccccxxx;    //
//    ccccc             lllldddflllllllllll            \___|\__,_|_|\__|_|\___/|_| |_|___/                               ccccccccccccc.           ccccccxxx;    //
//    ccccc             ;;..filllllllllllml                                                                              ccccccccccccc;.          .cccccxxx;    //
//    cccccccccccccccccccccccllllllllllllll                          cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc:xxx;    //
//    ooddl,'''',,',,;looooollllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllccccccccclodddddxxx;    //
//    odddddddddxxdddoooooooollllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllodxxxxxddd;    //
//    dxxdddddddxxdddooooooooooooollooollllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllooooooooodddddoooo;    //
//    dxkxddddddxxdddoooooooooooooooooooooolloooooooollllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllooooooooooooodxxxxdooo;    //
//    dxxxddddddxxddddooooooooooooooooooooooooooooooooooollllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllooooooooooooooodxxdddooo;    //
//    dddxxxxxxxkxxxxdddoooooooooooooooooooooooooooooooooollllollllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllloooool:::::::::cdxxxxxxxx:    //
//    ddxxd           ,cddoooooooooooooooooooooooooooooooooooooooooollllloolllllllllllllllllllllllllllllllllllllllllllllllllllllloooooo:.          .lxddxkk:    //
//    ddxx,           .ldoooooooooooooooooooooooooooooooooooooooooooolooooloooooololllllllllllllllllllllllllllllllllllloollooloooooooo,            :xxxxkkkc    //
//    ddxd'           .cddddooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooolloolllllollooooooolooooooooooooooooooooo,            :ddddddx:    //
//    ddxd'           .cdddddooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo:.          .lxxxddod:    //
//    ddxxc...........;oddddddoooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooc,,,,,,,,,;ldddxxxxkc    //
//    xxxxxdoooooooooodddddddddooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooodxxxxxxxxc    //
//    xxxxxxxxdxxxxdddddddddddddddddoooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooddxxxxdddd:    //
//    xxxxxxxxxxxkxdddddddddddddddddoooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooodoooooodddxxxxxxxxkc    //
//    xxxxxxxxxxkkxxxxdddddddddddddddddddddddddddooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooddddddoooodddxkkkkkxxxc    //
//    xxxxxxxxxxkkxxxxxdddddddddddddddddddddddddddooooddoooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooodddddoooooooodxkkkkkkxkl    //
//    xxxxkdolllllcccldxxddddddddddddddddddddddddddddddddddoooooooooooooodddooooooooooooooooooooooooooooooooooooooooooooooooooddddddddo:..........;dkkkkxxxc    //
//    xxxkl.          'oxdddddddddddddddddddddddollodddddddddoodooooooooodkkdooooooooooooooooooooooooooooooodddddddddddoooodddddddddddc.           :kkkkkkkl    //
//    xxkk;            cxxxddddddddddddddddool:;,';ccccloooddddddoooooddoodddooooooooooooooooooooddddddddddooodddddddddddddddddddddddd:.           ,xxxxxxkl    //
//    xxkk;            :xxxxddddddl::coddo;;;'.......'',;:lodddddddoddddddooddooddooooooooooddddoloddddddolc:clcc:clddddddddddddddddddc.           ,ddxxxxxl    //
//    kkkkc.          .lxxxxxxxxd:...;ldl,.............,:cldddddddddddddddddddddddddddddddddddol::odoooc:;:;''.....,:codddddddddddddddo;..........,ldxkkkxxl    //
//    OOkkxl:;;;;;;;;:oxxxxxxxxo,...,:ol,..............';cloddddddddddddddddddddddddddddddddddo;;lc::;,.';;'.......',,;::lodddddddddddddoooooooooodddxxxkxxl    //
//    OOkkxxkkkkkkkxxxxxxxxxxxo,...;ldl'............  ..,;cloooloodddddddddddddddddddddddddddo:,;c,'''..''.........','...'codddddddddddddddddddddddddxxxxxko    //
//    kkkkkkkxxxkkkxxxxxxxxxxd:...;col,...............';::::;;:::loddddddddddddddddddddddddddl;,:c;....................',:odddddddddddddddddddddddddxxxxxxxo    //
//    xxkkkkkkkkkkkxxxxxxxxxxd:..';clc'.............',;,'.',;:lloddddddddddddddddddddddddddddl:;;:,.................',;clllcclodddddddddddddddddddxxxxkxkkko    //
//    OOOkkkkkkkkkkkkkxxxxxxxd:...';::,............,'..',;coddxxdddddddddddddddddddddddddddddoc:;,...................''''.';:codxxdddddddddddddddxxxxxkxxxko    //
//    kkkkkkkkkkkkkkkkkkxxxxxkd;..';cc,...........,,,,,;cdxxxxxxddddddddddddddddddddddddddddddol:,'. ...... ......... ...,:odxxxxxxxxddoc:;;;;;;;;cdxxxkkxkd    //
//    kkkOkl,'.......':dkxxxxxxc..,coc'..........';;;:codddxxdxxxxxxddddddddddddddddddddddddddolcc;'....... ........ ....',;cloooddxxxo'           ;xxxkOkkd    //
//    kkkOl.           :kxxxxxkd,.':l;.......',,;;;:cc:::;:cclllloodxxxxdddddddddddddddddddddxdoll:,. ..........   .........';;;:clodxl.           'dxxkkxkd    //
//    kkkOl.           ;xkxxxxxxc''c:........';ccc;;,,,,,;;::::;;::ccodxxxdxddddddddddddddxxxxddol:,..  ......     .......',;;;;;,,:ldl.           'dxxxxxkd    //
//    kkkOl.           ;kkkxxxxkxl:;'.....,;;:;;;;,,,'''''',,,,;;;:::lodxxxxxddddddddxxxxxxxxxxol:::,........    ......'....',,,;;;;:lo,          .:xkkkkkOx    //
//    kkkkx:..........;dkkkkxxxxxxdc,'',:ccclc;,'',''...'''''''',;;;:cloxxxxxxxxxxxxxxxdoolloo:'....'';::;,'................,;;,'';cooddl::::::::cokOOOOkkOx    //
//    kkkkkkkxxxxxxxxxkkkkkkkxxdllcc;,:cc;,;clooc;:c:;;;:ccccc;,;;;;;codxxxxxxxxxxxxxxdl;'''''.........,,,,..',,,'................;odddxxxxxxxxxxxkOOOOOOkOk    //
//    kkkkkkkkkkkOkkkkkkkkkkkxxolllc,''...',;clddolodddxxxxxxxdddoollodxxxxxxxxxxxxxxxxl;'';c:'..''..''...',',;,'..................''',;::codxxxxxxkkkkkkkOk    //
//    kkkkkkkkkkkOkkkkkkkkkkkxxxxxxxl'...';:cc:;,',coddxxxxkkkkkkkxxxxxxxxxxxxxxxxxxxxxdlc:colcclol:,',. .;:;;;'........  ..',,,'',,;::clllodxxxxxkkkkOkkkkx    //
//    kkOOOOkkkkkOOkkkkkkkkkkkkkkkkkkc.':oddxxd:'..',;:ccc:::ccldxkkxxxxxxxxxxxxxxxxxxxxxxddddddol;'''.....';::;'.........',;cloloodxxkxxxxxxxxxxxkkkkkkkkkk    //
//    OOOOOOOOOOOOOOOOkkkkkkkkkkkkkkkl'ckkkkkkkdolc:,.'',;:::;;,';cdkkkkkxxxxxxxxxxxxxxxxxxxxxxxdlc:cllc:cc'..,;;;,;;,''...'';codxxxxxxxxdddddddddxkkOOOkkkk    //
//    OOOOOkocccccccccokkkkkkkkkkkkkkl,lkkkkxxkkxkkxdo::,.',,,;,...':lodxkkkxxxxxxxxxxxxxxxxxxxxxxxxxxxocokdc,..,;,;oxxo:;;,;::;;cdxxxxl'..........ckkkkOOOO    //
//    OOOOx,          .ckkkkkkkkkkkkxlcdkkkkkxkkxxkkkkkoc:c:,,;,'.......;ldxxkkkxxxxxxxxxxxxxxxxxxxxxxklcdkkko;..,;,cxkkkxxdlllc::cdxxd'           .dOkOOO00    //
//    OOO0o.           ,xkkkkkkkkkkkoclxkkkkkkkkxxkkkkxc:looc;;,..........,;codxxkkkxxxxxxxxxxxxxxkxoddccxkkkooc';:;lxkkkkkkkkxxdddxxxd'           .dOkkOOOO    //
//    OOOOo.           ,xkkkkkkkkkkxl;lkkkkkkkkkkkkkkxlcl:;:;'...............,:ldxxkkxxxxxxxxxxxkxdlcol;:ooddloxlll:okkkkkkkkkkkkkkkxxd,           .dOkOOOOO    //
//    OOOOx,          .ckkkkkkkkkkkd;;dkkkkkkkkkkkkkdccol:,''......   ........,coxxkkkkkkkkkkkkkkdc:c:;::;::ccloxkkkkkkkkkkkkkkkkkkkkxxo           ';::coxkO    //
//    OOOOOxoccccccccldkkkkkkkkkkkko:okkkkkkkkkkkkkkxdlc::;,.. ...         .  ..;::cldxkkdoloxkkxl',;';l:;;,;,:oolloxkkkkkkkkkkkkkkkkk:;:::'......;:::::burn    //
//    OOOOOOOOOOOOOOOOkkkkkkkkkkkkxllxkkkkkkkkkkkkkkkkxl;'''.....          .. .....':oxkxc'..okkd:...,lc,,,,,;c;'''';lxkkkkkkkkkkkkkkkkkk,,,,:lx0;;;;;;:film    //
//    OOOOOOOOOOOOOOOOOOOkkkkkkkkkxodkkkkkkkkkkkkkkkkkkd;......,'           ...';:cldxkkxo:,.,dkd,...;l,.,'',,'.',,;:cxkkkkkkkkkkk..........l. ...';::;;;;;;    //
//    OOOOOOOOOOOOOOOOOOOOkkkkkkOkdoxkkkkkkkkkkkkkkkkkkxc,.......           .';lxkkkkkkkkkkd;.,ld:..'c:..'','...':oxkxddxxkkkkkkkkkkkkkkkkko,  ....;clc;'',;    //
//    O00OOOOOOOOOOOOOOOOOOkkkkkOkdoxOkkkkkkkkkkkkkkkkkkxl'....    .     ..,:oxkkkkkkkkkkkkxxl',cc;.;l,...''..';clc:::cldxkkkkkkkkkkkkkkkkkx;......:llc:'...    //
//    00000OOkkkkkkkkkOOOOOOOOOOOxddkOkkkkkkkkkkkkkkkkkkOko,..'.... .......,:::::cllloxkkkkkkko'':c,:c.......':c:,';ldxkkxxxxkkkkkkkkkkxxxxxxxxxxx.,;;,'...'    //
//    OOO0Oo,.........'oOOOOOOOOOdoxkOkkkkkkkOOko:;,,',,;::,':c............',:c::;:llcoxkkOOkkOd,'::l;.......','';cllccccclodxkkkkkkkk.            ,:::clddx    //
//    OOO0k'           'xOOOOOOOkdoxOOOOOOOOOOxl;;;,',,'..................',,,,,;;;;:cllloooxOOko;':l'..........'','...;lodxkkkkkkkkkx::            ';:ldxxk    //
//    OOO0x'           .xOOOOOOOkdokOOOOOOOOOkl:::::cldo,............. .....',;;;,;;;:c:;;;;;cldko:cc,'''..........,;coxkkkkkkkkOkxdd;.:             ,ccoxkk    //
//    OOO0k,           'xOOOOOOOkddkOOOOOOOOOkocloddxkOkc....';l:.,oc........,cclllc:;:c;;::;;;,:oclc;,......';;;:ldxkOOOOOOOOOko::lxc:.          .,:lolc:;x    //
//    OO00Od;'''''''',;dOOOOOOOOxodkOOOOOOOOOkxddkOOOko:......;xd',dl,'.. ...,ldxxo:'..',;;,',;,:ccl:,,'.....';:cllooddxkkOOOOko,.,lo;.;:codol:,,,,,,xxxxxxx    //
//    OO00000OOOOOOOOOOOOOOOOOOOxodOOOOOOOOOOOOOOOOxl;,'....';ckx;;,.','......'';::cooollol:,''..':l'....,;,''''..'''',;:lxOOOko,.,;....ddddddddddddd::lddxx    //
//    OOO000OO0OO0OOOOOOOOOOOOOOxoxOOOOOOOOOOOOOOOOxloxo,..,:ldOx,,;...''''''''''.';cdkOOOxc'....,cl:'.'clc;,',;'''''''.',;:codo:,,................;::cooldx    //
//    O000000000000O00OOOOOOOOOOdokOOOOOOOOOOOOOOOOOOOdc'.'cdxk0x,;l' .',;::,'',;:::::cldk00kc,,,:oodo:dOo,... ....';ldooddolllol;,'............. .,;::;,,lO    //
//    0000000000000000OOOOOOOO0kodkOOOOOOOOOOOOOOOOOOxc:,.,oOOO0k:cx;...;coddlc:okkOkkkdlcdo,.,,;lddko;d0Ol...    ...;xOOOOOOOOOko;........  ......;cllllodk    //
//    000000000000000000OOOOOOOxodkOOOOOOOOOOOOOOOOOOkoc:',dOOOOOllx:...,:oxOOOxdxkOOOOOOd;...'':oxO0l'd00d;''........;xOOOOOOOOOko;...............lxxxxdlcc    //
//    00000Oocc:::::::lxOOOOO00xodO0OOOOOOOOOOOOOOOOOOkdllokOOO0Oockd:'.':oxOOOOOkOOOOOOx:'';;',lxOOOc'd0Odldl:;'.''...cO0OOOOO0Od:'....           .lxdxdlll    //
//    0000O:           'x0OO00OxoxO0OOOOOOOOOOOOOOOOOOOOxxkOOOO0OocxOxl'.,:xOOOOOOOOOOOkl:cooxocdO00O:,x0Ol:xOdl:,':lc..;lkOkdlloo:.....            ;ddddddd    //
//    0000O,           .d0O000OxoxO0OOOOOOOOOOOOOOOOOOOOOOOOOOO00dcx00kc:llxOOOOOOOOOOOdclxO0Olcx000O;'k0O:.d0Oxl;.;xOxl;'';;,',cllc:,,.            ,ddxxkO0    //
//    0000O,           .d0O000OxoxO00OOOOOOOOOOOOOOOOOOOOOOOOOOO0xcd000OkxxkOOOOOOOOO0OdodkO0kclk0O0k,,k0O,'k0O0Oxolx000kc...:ldkOO0o',,.           ,loddxO0    //
//    00000l.         .:k00000OddkO00000000OOOOOOOOOOOOOOOOOOO000xcd000000OOOOOOOOOOOO0dcd000d:oO000k;:O0x';O000000OkO000xc:coxOO0O0k:'''..........,:;;;;;:c    //
//    000000kdooddddddxO000000Oddk000000000000O0000000000OO000000kloO00000000OOOOOOOO00Odx00OocxO000kloO0d'l0000000000000OkkOO0000OO0kc:c:;'....',,,,coooddd    //
//    000000000000000000000000kddk0000000000000000000000000000000OooO00000000000000000000000xloO0000kld00o.l0000000000000000000000000Ooclodd,'c,...',cl::cok    //
//    000000000000000000000000xodk00000000000000000000000000000000dlk0000000000000000000000Olcx00000klx00l.o0000000000000000000000000Ol,:okk:;kd'...';;,;,,c    //
//    000000000000000000000000xodO00000000000000000000000000000000xlx0000000000000000000000dcoO00000kox00l.o0000000000000000000000000d,.,cdx;,kOl,''.'ccc:;c    //
//    0KKKK000000000000000000OxdxO00000000000000000000000000000000kloO00000000000000000000kclk000000xok00o'o000000000000000000000000k;..;lkk;.x0ko:,,:oodxdo    //
//    0000000OkkkkkkkkO000000Oddx000000000000000000000000000000000OooO00000000000000000000ocdO000000xdO00o;d00000000000000000000000Ol''',;;,..';;,.'::;,;oxx    //
//    00000x,..........:k0000kdok0000000000000000000000000000000000dlx0000000000000KKKK0Kxclk0000000xdO00o,dK000000000000000000000Ol,,;,.           ;dlllcx0    //
//    00000:           .o0000kodk0000000000000000000000000000000000kld00000000000000KKKK0ocx0KK00000ddO0Ko,dKKKKKK0000000000000000d,',l;            ,O0OOxk0    //
//    00000;            l0000xodOK00000000000000000000000000000000KOolOK00000KKKKKKKKKKKxld0XKKKKKKKdd0K0o:kKKKKXXXXXKK00000000000o,,cxl.           ;OKKKKKK    //
//    00000c           .dK0K0xoxOK00000000000000000000000000000000KKxlxK0000KKKKKKXXKKXOllOXXKKKKKKKxdKXKdlOXXKXXXXXXXXKKKK0000000o;lx0k;..   .....'d0KKKK00    //
//    00K00Ol;;;;;;;;;:d00KK0xox0K000000000KKKK00000000000000000000Kkld00OO00KKKKKKKKX0dlxKXKKKKKKK0dd0KKo:kXKKXXXXKKKKKK00000000Oc:x000dll,'cxxxxkO000KKK0K    //
//    xOOxkO00000000KKK0000KOddkKKKKKKK00000KKKKKKKKKK00KK0000000000klokOkkkOO00000KKOolx0KKKKKKKKK0dd0KKockKKKKKKKK0000000000000OllO000koc;;dOOOOOO000000O0    //
//    ;:::cok0KKKKKKKKKKKKKKOddOKKKKKKKKKKKKK00KKKKKKK000K0000000000kllxOkkkkkkkOOO0OdcdOK00000000K0dd000dlkK0000000000000000000OOxxOOOOOo;;ck0OOOO0000000O0    //
//    .',:clodxk0000KKKKKKKKkddOKKKKKK00KKKKK0000KKKK00000000000000K0ocx00000OOOOOOOdcok0OOO0OO0000OdxOOOolxOOOOOOOOOOOOOOOOOOOOOOOOOOO00x:;oO00000000000000    //
//    ..,,;;::ok0000000000K0xodOKKKKK0000000000000000000O00OOOOOO0000xcd00KK0K00OOOklcdOOOOOOOOOOOOkdxOOOdlxOOOOOOOOOOOOOOOOOOOOOOOOOOO00Oc;oO000000KKKKKXXX    //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract DAYDREAM is ERC1155Creator {
    constructor() ERC1155Creator("godaydream editions", "DAYDREAM") {}
}

