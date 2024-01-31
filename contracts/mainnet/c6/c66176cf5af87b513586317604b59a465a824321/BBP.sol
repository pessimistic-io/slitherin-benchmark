
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: Bigeggs Black Pen
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                            //
//                                                                                                            //
//             .~77~.                                                                  ^P@@@@@@@@@@@@@@@@@    //
//           :!7~:                   .:~?YPGGGGBPYJ7^                                   .Y@@@@@@@@@@@@@@@@    //
//        :~!~:                   :?PB&@@@@@@@@@@@@@&B?.                                  7&@@@@@@@@@@@@@@    //
//      :!7^                    !P&@@@@@@@@@@@@@@@@@@@@#J.                                 !&@@@@@@@@@@@@@    //
//    ^~~.                    :G@@@@@@@@@@@@@@@@@@@@@@@@@G^                                 !&@@@@@@@@@@@@    //
//    ~.                     ^#@@@@@@@@@@@@@@@@@@@@@@@@@@@#~                                 J@@@@@@@@@@@@    //
//                           P@@@@@@@@&&&&&@@@@@@@@@@@@@@@@B.                                :B@@@@@@@@@@@    //
//                          ^&@&@@@@&GPGGBP#&&@@@@@@@&PB@##&J           ~~7?!!^:        ....  7@@@@@@@@@@@    //
//                          ^&@@@@#P#BGB##B##G5P#&&&#B#BBB#PBJ7~!!7.  :5G###BGGP?~.           :#@@@@@@@@@@    //
//                          .B@@&#?P#B##@&&B#&&B&&BBB####&&&#&&##&#Y?75B5BGBBB##BBY:          .5@@@@@@@@@@    //
//                           ?@@@&P##GB&&@&&###BBGGGPPBGYBGPP#&BB&@&#&GY5G&&&#&@##5            ?@@@@@@@@@@    //
//                           .5@@&5B##G&&BG5J7!7!?JJJ5PG?YJJ7Y55YPPYPGBBYYG##&&&&&?.         . !&@@@@@@@@@    //
//                            .?&@#&&#BBP!~..^^^^~^:.:?Y77~.^:^!^!~!77YY5YYBBBB#&7           . 7@@@@@@@@@@    //
//                             .^5#&BY77~. .:!??!?7^  :. ^::^^7JJY!7J~7!7PYY5P#@#7:            Y@@@@@@@@@@    //
//                               ^B#PJ^:::^~JY5GPGBG?.  .^:JB###B#BPJ!^7!J55YP#&&&?.      ^.  .B@@@@@@@@@@    //
//                             ^YBG5?^..:755##&&#&@@#~.:??G@&@@&&&&@#5!?7?5YJ5G###P!^:^!~?5J: 7&@&@@@@@@@@    //
//                          ..~YBGJ7:.:~!####B@??&@&&BPPYJ&&&&&@Y7#&&#PYY??YY55###BG7!~5G5PG7!BGG5G&@B&@@@    //
//                         .:~?#GY^~^.^JG&&&BGGBB##BB##BBGBGB#&&&&#&##BG75YJYYGPBB##57!5G5YY7Y5JJJ!PG?&@@@    //
//                           :5G!:~~..^7BGBGJ77?~J@#PP#@&#&&#~?YJ5G##&#BY75J?5PGGG###Y?YBYJ!7?7?J~:!77PBB#    //
//    !!!!~^^::...          .!BP::^ :!^!?~~:.^:  .?Y77&BBGGG7:~!~^^~?J5G??75?55PB&#B#BPPGY5YJ?J5?!~~ .?Y7?    //
//    ~~~~^^^::::^~~.       .Y#7~J!:??!?77!7.  :..:.:!B5~^.: :^^~^: :.~7!!77?55G####@GJGG5??YJG55JY^^5J^7?    //
//        ..::^~^^^757^^:. .^GY^!7~!YYYGBBP#P~::^^~~7?GJ^...^^:..:::^!~!~!^?JYJP5BG&@#B#GG5Y5#5?J5!JPJ~!7J    //
//    .::::.    :~7J5G&&BPYY55YJ?JJ?PPY5GB&##BPJ!~7JPBBGJ!: ::!~:.:7????!!!?JP5P5BB#GB#BB##GJYY??~777J7!77    //
//    ^^~!?Y5Y?J??Y55GY7~:^JBB5???~JJ!J~7?5?YY?5Y!7?J555GGJ!?YPGYJY5Y?7!!?JJ?JJJPG#GGB&&GGG##PPJ7J55Y?!777    //
//    7JPBB?^::~7????~ .~!5BPPJ7?YJ!.:! . :. ...::~!??~^^.^7?JY?~^.^^7?~77755YBPG5B#GG##BB?P&&@G5GPJYP?7Y5    //
//    YJ~77 .~!~^:^~. ?P!~J5Y5??7J?7!!!Y?:7!!~~7PGJYJ??J!!~::7!^~:::?J7Y!!YPJYGPGG5###GG#&GG###&Y7JP5YP5GY    //
//     .~~.^7^.:^^:  !&!7JJGG5JJ??Y77?~5G??!!G5PG5GYGPG!P#GJJ?YY555JPPP5J?G5YPBGGBGGPP#BBPBGBG#&G5YP555YPP    //
//    ^~.:7!~~~:.    J&GG5G#PG??!J?7!~!PB&BGYB75BG#BGGYJ#&&GY#GPB#BG&&J~?5JBP5PGB##&BG#&BPGBBGBPB#YPG5YYYJ    //
//    ..7J~::     . 7PYP7YPB#P5JYJ^~7JJJYBBPPPYJGP5GGGYBP#GGBP5B#GP##G5?PGGPGBBGB&###&#GP##&BGB#B#GJPYG5PG    //
//     !!  .:^!!!?!?#!:~!BG#&PG5?J!:7?YGGB#PBGGGYPP5PBBPBYP#BB#BBBGBPJ5?5BPY#BY#5#B#&5JJ5###&BPP7~7J55PJP&    //
//    :.:7JJJ5PGJG5PB7~^7B&&BBBYG5J?J~J5#BBBG#BG#5#GG&BBBJ#BB##GGGGPGPPYJGGG##Y&##&@&555B&@PJP~!!75GYJYB#P    //
//    ?YBGPYJ??JJP#G~.  ~5&B#&GPB&GJG7YGGBBGBPBBBPGG##BG55&#B&###PP#JYGJ5GGP&&B&#BBGYYGB#5YJ~?~7?5?!J5#P7J    //
//    GBP?PP?Y?7JYB5   .~JGGBB##PBBJB5YP55GBBBBG#BGP&PBG5#&@&&B5&G##7PG5##BG#&B&#5PGGBPJ!57555GJPPY^PY!7P~    //
//    GYYJ?J7~JYYPPJ:7Y?YPGBGG#&BPBBGG?5GYPGB#BB##5YGG##B@&&BBB7#YGBJP#5#@###@G#GGB&BB^P55PBG5PYYYG!7J?PJ?    //
//    B5YJGJ7?B?JP77#5~^^~B##B#&#PBBGB?5B55Y5#&B#@5BP&#B&&BGGG#?B5#GY5&BP&@#BBGBB##Y^G575P5PGJ!!J!PYJY~~??    //
//    P??7P55?JJ??JY5:  .:Y##@&@##&##&PP#BGP5#5YG&G&GB##&G5BPGBG#G&G5G&#&#PYYYP5PGY7J7JGBY55YJJYP5~:??7YJ?    //
//    G7J?^JYYJ!~?5P7^~^^^YB#BBB#&&###BBG#B#PB?JG&BGP#&@&P5BB#G&BB#BGB&##5?YBG5BG7YPYG#&Y?PYB#P^:BB5Y5?!JP    //
//    BY?7JGBPB7?575Y7~!~?P!^:!YJJ#&BG##BB##G#B5PBPBBB&&&B#&&B#BJ!!?YJJ5GJ5GB#BP!7BGG&GB#PY7Y5J!JGBB5BGP#?    //
//    57JPB7?G?PY!^5??PJY5^ :~~~7J55G55?7??5B#5B#PGB5P&&&###&&G~~!~!77YYJPPG#&P5?J5YPGG#G?~7^PBGGGPY7??JJY    //
//    GP?JP!~~^GB^7?5J55B5 ?J??7?JP?~~^.:!?JG#!7G#P5P#BYY?7JG@G^5JYYYJBB7P###GPP?J5JJ?BBP?^7?P#BYGJ~5JJP~~    //
//    &G?P~ :JP5JPYPPYJJJG7!555J!7G^ ^!75YPG##BPPB#&#&YY?!5PJ5B?GPGGGBG5?#&GYP?5P5J:!Y7B57!GY75##P?YPJPP5P    //
//    #BYB!. .:::JG5G#BBP?GG5JJ?J5BY.?YG#G##&?!BGGG###P?5Y5BG?GB5Y55GP??B@&5!5GBPGGJ7Y7BBP?!J&GYJ!:?B###B?    //
//                                                                                                            //
//                                                                                                            //
//    Bigeggs Black Pen                                                                                       //
//                                                                                                            //
//                                                                                                            //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract BBP is ERC721Creator {
    constructor() ERC721Creator("Bigeggs Black Pen", "BBP") {}
}

