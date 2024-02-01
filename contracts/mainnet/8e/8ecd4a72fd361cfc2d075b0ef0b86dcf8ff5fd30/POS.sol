// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Path of the Sawulak
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                            //
//                                                                                                            //
//    PPB&@@BGB&@@#BBB&&&&@@@&&&@&&#B#&&#&@&&@@&BB##BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB    //
//    B#&@&##&&&@@BGGB#&&&##BBB#@@@&B&@@@@@&#&&@&#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB    //
//    &&&&&&@@##@&&&&@&&&GGGGGBB&@@@#&&@&&@@@&B###BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB    //
//    &&&&@&&&&&&&&@&@@&&#GGGBB&&##@@@&&&&@&&@&#BBBBBBBBBBBBBBBBBBBBBBBBB##BBBBBBBBBBBBBBB#BBBBBBBBBBBBBBB    //
//    GGB&&&#@&@@&&&&@@@&@&&#&@&BB#@@@@#&@@&#BBBBBBBBBBBBBBBBBBBBBBBBBBBBB&&#BBBBBBBBBBBB#&&&#BBBBBBBBBBBB    //
//    GGG#@&#@&&&##&&&B&&@&&@@&##&@@&&&&&###BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB#&@&BBBBBBBBBBBBB#&@&#BBBBBBBBBB    //
//    GGG#@@@#BBGGG#&&&#@@&&&&@&@&@@#BB#&&#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB#&@@&#BBBBBBBBBBBBB&@@&BBBBBBBBB    //
//    B#&@@@&GGGGGGG#@@&&@@@&&@@@&#&&&####BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB#@&@@&BBBBBBBBBBBBBB#@@&#BBBBBBB    //
//    &&&&#@&GGGGGGB&@@&#BBB&@@@&#BBB&&&BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@##@@#BBBBBBBBBBBBBB&@@&BBBBBBB    //
//    &#&#B#@&#BBB#&@@&BBBB#&@&&@&#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@&&@@&BBBBBBBBBBBBBB#&@@&BBBBBB    //
//    B#@&#&&&@&&@@@&@&BB#&@@@&#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB#&@#@@@&#BBBBBBBBBBBBGB#@&&#BBBBB    //
//    GGB@@&#&@#&@@&@@&&&@@@&&&&BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@&P@@&@#BBBBBBBBBBBBP#@@&&#BBBBB    //
//    GG#@@##BB##&&@&#&#&@@&&#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBGGBBBBB#@@PG@#&@BBBBBBBBBBBBBB&#&&&BBBBBB    //
//    GB&&#GGBBBBBB&@@@@@@##&#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB#@@55&BB&&BBBBBBBBBBBBB&##5B&BBBBBB    //
//    &&#&#BBBBBBBBB#&&@@@&BBBBBBBBBBBBBBBBBBB#BBBBBBBBBBBBBBBBBBBBBBB#@&??&##&@&BBBBBBBBBBB#&&&PB#&#BBBBB    //
//    &@@&&###BBBBBB#@@&&##BBBBBBBBBBBBBBBBBB#&@#BBBBBBBBBBBBBBBBBBBB#@&?7#&##&&BBBBBBBBBBB#&&#?PGB&BBBBBB    //
//    B&@&@@&&&###B#@@@&&##BBBGBBBBBBBBBBBBBBB&&@@&##BBBBBBBBBBBBBBB#@#??###&@&BBBBBBBBBBB#@@&#55#@BBBBBB#    //
//    @&&&&&@@&&&&#&@&#&&#BBBBBBBBBBBBBBBBBBB#&&&&@@@&##BBBBBBBBBB#&&GJG##BB&&BBBBBBBBBB#&@&B#BB#&#BBBBBBB    //
//    @&BB###&@&B#&&&#&@&BBBBBBBBBBBBBBBBBBBBB#&&&&&@@&&#BBBBBBBB&@BY5#@B#&&&#BBBBBBBB#&&@5!?BB#@&BBBBBBBB    //
//    @#B#####&@#&&&#&&##BBBBBBBBBBBBBBBBBBBBB###&&&@@&#&&BBBBB&#PJJG&@@&&@#BBBBBBBB####&#YJ5B#&&BBBBBBBBB    //
//    @@&#####&@@@&#####BBBBBBBBBBBBBBBBBBBBBBBB#&&&&&@&&@&#&@@P7?5&&&&@@&#BBBBBB#&#&#P5#GBBPP##BBBBBBBBBB    //
//    #&&@&&&&@@@&&###&#BBBBBBBBBBBBBBBBBBBBBBB##&@@&##&&@@@@#GG&&&#&##&@&#&&##&&BBB#BY?YG&&@&#BBBBBBBBBBB    //
//    #&&@@@&&@@&&&&#BBBBBBBBBBBBBBBBBBBBBBBBBBBB#&&&##&@&#&&BJG@&&&@##BB#&B&@&&@BP&##BGPB&&#BBBBBBBBBBBBB    //
//    @@&&&&#@@@&&@&BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB#&##B#&##P#&&@&&&&#&&#GB&B#&PB&GPGG##@#BBBBBBBBBBBBBBBB    //
//    @&#####@@&#&&##BBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@#B5JJB#@&B@BB&G#&G#&&&5#&GB5Y#&#&B#&#BBBBBBBBBBBBBBBBB    //
//    @&####&@@&&&&##BBBBBBBBBBBBBBBBBBBBBBBBBBB#&G55YJP5P5P#G5GGBBB&@@@@&BB@&PYY##G#&&&#BBBBBBBBBBBBBBBBB    //
//    @@&&&&@@&#&####BBBBBBBBBBBBBBBBBBBBBBBBBB##B5J?YBBPBBYPB5P&#P&#&@@@&##@#YYG&#BPP&@&BBBBBBBBBBBBBBBBB    //
//    @@@@@@@&&@@@&#BBBBBBBBBBBBBBBBBBBBBBBBBB#&Y~!?BB5PBPPP5B&5Y5GG#&&BG&&@#55###B&@&&@#BBBBBBBBBBBBBBBBB    //
//    &&@@@@&##@&##BBBBBBBBBBBBBBBBBBBBBBBBBB#@5~~?Y5GPYYYPB5YYPG5G#G&GYB@@&GB@@&BG#&@@@@#BBBBBBBBBBBBBBBB    //
//    @@&@@@&#&@&&BBBBBBBBBBBBBBBBBBBBBBBBBBB#@Y7Y5PBPYYYYYJYYYG&@GP&#Y5&@#GB&@&@&&&&@@&@#BBBBBBBBBBBBBBBB    //
//    @&#&@&#&&&##BBBBBBBBBBBBBBBBBBBBBBBBBB#&@BYPGYYYYYYYYYYP#BG####&YYB@##&@@@&@&&&@&&&#BBBBBBBBBBBBBBBB    //
//    @&&@@&#BB#&#BBBBBBBBBBBBBBBBBBBBBBBB#&@&&#GYYYYYYYYYYY5GP5YBGB@@#P#@&#GGBB#G&&#&#B&&@&##BBBBBBBBBBBB    //
//    @@@@&##&&&&BBBBBB##BBBBBBBBBBBBBBB#&@@&#@@GYYYYYYYPPY5555GGGB#B#&##&&#GPPGGY#B##GB#@@@#&&#BBBBBBBBBB    //
//    @&@@&#BB###BBBBBB#&&#BBBBBBBBBBBB#&@@GB@&BP555Y5P#&5YGGGPGGG5B@&BG##G#@@@@&###&BPGG&@@&@@@&####&#BBB    //
//    @@@@&&&#BBBBBBBBBB#&@#BBBBBBBBBB#@@BG@&GP5G##&&&@&BPPGBG#BGBB#&&&&P#BYB@@@@@@@&@@&&B&##&&&&&&&##BBBB    //
//    @@@@&##B##BBBBBBBBBB&@&#BBBBBBB#&5YB&##PYYYY555PPP5YY5P5GGBGB##P#&YB#YG@@@@@@&@@@@@&&&&&BBBBBBBBBBBB    //
//    &&@@&&BBB#&#BBBBBBBBB&@@#BBBBB#B#G55GBYJYYYYYYYYJYYYYYYYYPG##B@&##&@#B#&@@@@@#@@@@@&&&&&&#BBBBBBBGBB    //
//    &&@&##BBBB#&@&#BBBBBBB&@&&&BB&&#GP5BPYYYYYYYYYYYYYYYYY5PYG#G&@@@GG&@@@@&@@@&&&@@@@&&#&@@&#BBBBBBBBBB    //
//    &&@###BBBBBB#&@@&##BBBB#&G5#@&GBPGGYYYYYYYYYYYYYYYYYG5YB#5B&#&&&@&G&&@@&B&@@@@@@@@&&&&&@@&###BBBBBBB    //
//    @@&##BBBBBBBBBB#@@&####B#&P7Y&@@B#5YYYYYYYYYYYYYYPPYGBP5B&G#@&5##5BB#@#5G@@@&&B#@&#@@@#B@&####BBBBBB    //
//    @@###BBBBBBBBBBBB##&&##&&@@B7~?GBG5YYYYYYYYYYY55GPGG#@@&#&B#@BY&G5@5G@#YG@@&&&GB&&PG&##PG##&&&#BBBBB    //
//    @@&BBBBBBBBBBBBBBBB#&&&@@@B&@G~.^JBBPYYJJYYP##&&B&@@@#&##BYB#&55B#&PYP#&#&&@&#@#B@&#&&##BBGB#&##BBBB    //
//    &##BBBBBBBBBBBBBBGBB##@@@@#&B#@5^.:~YGBGG#&#&&&&#@@@&#&&@#PG&BBGPB&&BPY5#@&BB&&&&####@@@@&&#B###BBBB    //
//    &BBBBBBBBBBBBBBBBB##&@@@@#&###@@&57:.!B@@&&#&#&@&@@@&&@@&PP###BPP#@#P#BYY&@GJP#@@#@B5B@#G#&G#&@@&#BB    //
//    #BBBBBBBBBBBBB#&&#PP&&GP#@&#G&B#@@@BG&&#&#&&&#####&@#&@@&&#PPYP&#@@GYY##G&@5YB#&&#@BB&@B5BBG?@#P&@@&    //
//    BBBBBBBBBBBBBB&PJ?J~G#5&#&&&#B#&@&B&&#@#&@#BBBBBB#@@&&BBGP&@PJP@&&#5YB@@@B##&@&##G&&B@&&5G&&?75?PP&@    //
//    BBBBBBBBBBBBBB&77&#!JBB#GB&&&&####&&&&#&###BBBBB#&@&&&&&@#&@PG&#P#55P&@B5P&&G&#&&B&BY#G&5GB&P:7?7!G#    //
//    BBBBBBBBBBBBBB#BYG#BPGYJBBB@@@@&&&##BBB&BP&BBB#&@@&&@@&&@&&&&@#P5#5YYG#YJG@G7&B@&P&G7BG#GG&#&J:Y~?&G    //
//    BBBBBBBBBBBBBBBB#&@@&#&G#@@&&###BBBBBBB##G&BB#@&#&&&&PYP@##B&#G~G@#BGGPBP5@Y^###&P#B?G#&&#&&&5JG?^B#    //
//    BBBBBBBBBBBBBBBBBB##&#####BBBBBBBBBBBBBB##BBB&&&##G&BG7PBG###P5:^#??5GPPB#G^.Y#&@BBP5J#&&G##BBGJ.Y!!    //
//    BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB#@@&&P5&#&YBPP#B#&B^.PY~YYYJP&Y::!P&@#B&#P##&P#&#B5G?!7^    //
//    BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@&&GPJBJG!5BB####G~~BG~7YYYG&?.~^^B@@@@&#PPY5&@@&P#@Y5~    //
//    BBBBGBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB@@&B#PJPY5!YGP&###B!:7#Y!YYYB&!:..Y@@#&@#GGGYG&@@#G&&YB!    //
//                                                                                                            //
//                                                                                                            //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract POS is ERC721Creator {
    constructor() ERC721Creator("Path of the Sawulak", "POS") {}
}

