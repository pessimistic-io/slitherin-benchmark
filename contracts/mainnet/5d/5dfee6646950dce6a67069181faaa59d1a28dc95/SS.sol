// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: SATUSEKTE
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                            //
//                                                                                                            //
//    #BB&#B###&&&BGGGGGGBPJ7Y5YYG#BBBBBBBBBB#BB#&&&@&@@@&&&&&&#BBB#BBBBBBBBBB#PYY5J75GBB#B#BB#BGGGGGGGGGG    //
//    GG#&#&@@&&#BGGGGGBGJ?JYYYPBBBBBBBBBBBBBB#BBBB##&&&&&&&##BBBBBBBBBBBBBBBBB#B5YYY??5B##B#&@&&#BBGGGGGG    //
//    B##&@&#BBGGGGGGBPJ?J5YYP#&BGBBB#BBBBBBBBBBBBBBBBBBB#BGGGGBBBBBBBBBBBBBBBBB#&G5YYY??5B&&GB#&&@&&##BGG    //
//    B&&#BGGGGGGGGBGJ?Y5YYPBBB#&BBB#BBBBBBBBBBBBBGPYJ7!~!~!?Y5PGGBBBBBBBBBBBB#&&BGBG5Y55J?5BBBBBB#&&@@&&&    //
//    BGGGGGGGGGGBGJ?YP5YPBBBBGGBB#BBJBBBBBBBBBGY!^^^^~~!~~~^::^!?JPBBBBBBBPBPG&BGGGB#G5Y55J?5B#BBBB##&&@&    //
//    GGGGGGGGGBGY?YP5Y5BBGGBBBGGB&&BY5BBBBBBPY??JYYYYYJJJJJJJJJ?7!~?GBBBBBPGYPBGGBBBBB#B5YPPJ?5B#BBBBBB#&    //
//    GGGGGGGBGY?5P5Y5BBBBBBBBBBGGG#&YP5BBBGY5P55YYY55PPPPP555YJJJJJ??5GBB##GPGBBBBBBBB&&BGYYPPJ?5B#GGBBB#    //
//    GGGGGBGY?5G5Y5BBBB###BBBBBGBGGBBYGGGBBB##BBBBGGPPPPPPPGGB##BG5YJJYB&#B#YBBBBBBBB##B#&&B5YPPY?5B#BBB#    //
//    GGGGGJ?5G5YPBBBBB#&###BBBBBBBGGBG5G#B#BPP5YJ7!~^::....::^!?YGBBGGGB#&#YGBBBBBGB&#G#&&&&&B5YPGY?5B#B#    //
//    GGB5?5G5YPBBBB###&&&#B#BBBBBBGGGGBPB&B5?!^:.................:!YGGB&&B5GBGGGGBB#BG#&&&&&&&&B5YPGY?GB&    //
//    P5Y5BG5G###B#&&&&&&##GGBGGGBBBGGBPPG?^:........................^75##PGBGGGGGB#PPGGBB#&&#&&&&#P5BG5YP    //
//    5YYYYP&&&&B###&##BBBGGGGBGGBGGGPBP7...............................~YP5BGGGGBBGPGGGGBGB##&&&#&&#5YYYY    //
//    GP55B##&#B##BBGBGGGGGGGBBGGGGGBP~:.................:................^YGGPPB#GPGGGGGGGGGGBB######GYPP    //
//    BBPYPP5BGGBGGBGPGGGGBBBBBGBGGGG!..................^~:.................^PGBBPPPPGGGPPGGGGGGGBB###55GB    //
//    G#BG5PGB#BBBBGBGGGBBB#GGGBP5YJ~.................:^!!~^.................7GGPPPPPPGPPPGPPPP5PPBBBGPGBB    //
//    &BGG5YGGBBBBBBBBBBBBBBGGPYJJ?^.................:^:::::^:...............^5YPGPPGPPPPPPP5PPPPGGGPPGGGG    //
//    #GGGGGGGPGBB#BBBBBGG5PYJ77?!:................:::.......:::..............YPYP55P55YY55YJY55PGP555PPPP    //
//    #BGPPGGPPPG#GGP5YYJ????7!7:................:^^...........~~:............^77??????????????JJYYY55555P    //
//    BBGPPPPPGPPP5Y??777?JY55~:..............:~?JJ7:......:^~7YY?!^............7BPP5YJ??????????????JYY55    //
//    #BPPPPPP55J??????JY55GG?..............:^!7?Y555J^..^!5555J??7!~:...........7YPGP55J??????????????JY5    //
//    BBPPPP5Y????????Y5GB5Y!.............^!!!?5YYJ777!..:~777YJY57!!7:...........^7JYPBP5Y?????????????JY    //
//    GGP55Y?????????55BBYY?^.............:7!~^~!^^^^!~...~~~~~!!^~!!~.............7?JJY#G5Y??7???????????    //
//    PGP5????????7?5G#Y5Y77:..............~!~:....:~!:...~~:.....~!7:.............~?!?JJP#PY7???7??7?????    //
//    Y5YJ?????77??5B&5JY7!7:..............:!!!!~~!!7!::::~7!!~^^!!7~..............^?!!7YJP&PJ7???????????    //
//    ???????777??Y5#GYGP5J7~...............^7!!!!!!!!!7!7!!!!!!!!!7...............~??J5G55BB5J?777777????    //
//    ???????JYPGPP5#YJBBBG?:................~7!7!!???777!7??7!77!7:...............?PYGBBPJP&JGPG5Y?77????    //
//    ?????Y5PGGPPYG#5JGY?~...................JY7!!???7!7!?J?7!!7P!...............:?Y55Y5PJP@5PPPGGP5J7???    //
//    ???JP##5YY5Y5P#PYY!:....................7J57!!!!!!7!!!!!!JY?^...............!YYJ??555G&55Y5YYP#BY???    //
//    ???P#BYY5J?7Y5GBJ!Y:...................:J~?BY!!!!!!!!!!7GP~7!...............:~!77JPJ5#5P?7?J5J5#GY??    //
//    ?75PBYYY7????55#5J5?..................~GB^!7B#Y?7!!!7JG&P~^7&~...............:!?YY5B&G5J7777?5JPGGJ7    //
//    77P#PJP7??7777Y5Y?BY...........:^^!?J:.!J:!!75B&&##&@&GJ!~^~&!:...............!YPPBGP5J777777?5J##Y7    //
//    ?7PGPJ57?7777!!7YY5GJ:^~~~~!!!7J!GG5J:..~!~!!!7JP##B577!!!~77~?J?!:....:!!~~~~JB&&B5J7!!7?????PJBGY7    //
//    J?5BGJ5??7?JJYJJ7!7!7~~~~~^^:::::?!:....:??!!!!!!!!!~!!!!7Y~^!J7JPGP:...:^^~~!!?JJJ????JJ?777YYYBBJ7    //
//    YJ?B&5J5JJJ!J!!!!!!!!!!!!!~~^:........^7!^!Y?!!!7!!!7!!7YJ~~?55J77757.:....^~!!!!!~!!!!7?!J?Y5JG@P77    //
//    YJJYBPPY5P!~77777777!!!!!!~:.......~~YBBJ?!~JY7!!!7!!!JP?~~?J5&@#GYGJ:!:...:~!!!77777777!~7GY5PBP?7?    //
//    5YYJJ5B&#JG77!!!!!!!!!!!^:......::YGY5J?Y5Y7~!J?!!7!75Y!~~??~7?5B@BYJ.^.....~~!!!!!!!!!7!YYP&&GY77??    //
//    5YY555Y5#Y@7!!!!!!!!!!!~.......:Y!~?YPB##PJ?~~~?J775P?~~~JP5J7?7YG!!~......:~~!!!!!!!!!!~5&Y#YYYJ?77    //
//    PP5Y??JB#BBJ!!!!!!!!!~~:.....:~:J!~!P#PJ7?YP?!!~!GGJ~~~!YJB@@#GPP~:.......:~~!!!!!!!!!!!!5#G&PJ?JYYY    //
//    ???5GBPY&J7J!!!!!!!!~!^.....:~^.?5~~75YPB&@#YJ?5G57!!!JP7!7JP#@5:.......:~!!!!!!!!!!!!!7^5~GBYGBPY??    //
//    GBG5?7~YJ.7J^7!!!!!!~!:.....^~!^~B!~~7B@&PJ775GPPJJYP#B5?????5?......:^^~!!!!!!!!!!!!!!7^5::5?!7JPGB    //
//    ?7!!!!JJ..!Y!7!!!!!!~!:.....^!7!.B?~!~!YYJYP#&5P@&@@@P5&@#G55!.....::!!!!!!!!!!!!!!!!!!?75:.:57!!!!7    //
//    !!!!!J?...~Y^?!!!!!!!~^.....:~!?^P5~^:^^7B@B5?7JB@@&J!7?YG&G!:....J!!7!!!!!!!!!!!!!!!!!7~Y:..^Y7!!!!    //
//    !!!!??....~J:!!!!!!!!!~:......^?~7G...:::!5JJYB&55#GY???7J5!~^....7^?7!!!!!!!!!!!!!!!!!~~J:...^Y7!!!    //
//    ^^~JJ.....~J:^!!!!!!!!!!:......:::P^..~~..~Y&&P?5PJB&&#PYY~~^^......~^:::^~!!!!!!!!!!!!.!?:....^Y7~^    //
//    .:JY.....:!?~:!!!!!!!!!!!~::......::.......:Y5?PY777JPB&Y::......:...:^^^..~!!!!!!!!!!!.?7~.....~5!:    //
//    YG5:....:~!7?^!!!!!!!!!!!!!!~~~~~^...........GGGB5?77?Y7........^B!!!!!!!::~!!!!!!!!!!~~J!!^.....~GP    //
//    BB:....:~!!!5!!!!!!!!!!!!!!!!!!!7!.........:55?YB@&GJY7.........?G:7!!!!~~!!!!!!!!!!!!~?Y!!!^.....!&    //
//                                                                                                            //
//                                                                                                            //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract SS is ERC721Creator {
    constructor() ERC721Creator("SATUSEKTE", "SS") {}
}

