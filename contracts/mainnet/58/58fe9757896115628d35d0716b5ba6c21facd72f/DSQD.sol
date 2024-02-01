
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: defiantsquid
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                            //
//                                                                                                            //
//                                                    .~~.                                                    //
//                                                .^7JYYYYJ7^.                                                //
//                                            .:!?JYY?~::~?YYJ?!:.                                            //
//                                         :~7JYJJJJ~      ~JJJJYJ7~:                                         //
//                                     .^7JJJJJJJY?:        :?YJJJJJJJ7^.                                     //
//                                 .:!?JYJJJJJJY?^            ^?YJJJJJJYJ?!:.                                 //
//                              :~?JYJJJJJJJJJ?:                :?JJJJJJJJJYJ?~:                              //
//                          .^7JJJJJJJJJJJJJJJ?                  ?JJJJJJJJJJJJJJJ7^.                          //
//                      .:!?JYJJJJJJJJJJJJJJJJJ!                !JJJJJJJJJJJJJJJJJYJ?!:.                      //
//                   .~?YYJJJJJJJJJJJJJJJJJJYP#&.               &#PYJJJJJJJJJJJJJJJJJJYY?~.                   //
//                  :!^^~7JJJJJJJJJJJJJJYPB&@@@J                J@@@&BPYJJJJJJJJJJJJJJ7~^^!:                  //
//                  ^YJ?!^^^!?J?!7?JJ5G&@@@@@@@:                :@@@@@@@&G5JJ?7!?J?!^^^!?JY^                  //
//                  :YJJJJJ7~^.    7@@@@@@@@@@@.                .@@@@@@@@@@@7    .^~7JJJJJY:                  //
//                  :YJJJJJJY?     !@@@@@@@@@@@:                :@@@@@@@@@@@!     ?YJJJJJJY:                  //
//                  :YJJJ77YJY?^^?G@@@@@@@@@@@@G                P@@@@@@@@@@@@P7:^7JJY77JJJY:                  //
//                  :YJJY: .^^::~5B&@@@@@@@@@@@@G^            :G@@@@@@@@@@@@@@@GYJ7~: :YJJY:                  //
//           55     :YJJJ?  .?GBG57.~PPPPPB&@@@@@@.           @@@@@@@BPPPPPB@@@P:     7JJJY: :7:        55    //
//          .@@.    ^YJJJ? ^@@J^~JY !&@@@@#JG@@@@~            ~@@@@GJ#@@@@&P!7J.    .7JJJJY: Y@5       .@@    //
//          .@@.    .!!?J~ 5@G  :7!Y&@@&#B##:B&#?         :#5  ?#&G.B&&&@@&#BPY^.:^~7?JJJ77:           .@@    //
//      .!7!!@@.   ^77!.  ^B@#~!!7!!..:~!77!.  :: ^77!.  :5@@~~. .~77~. .:^7?7^^^ .~^ ~7 :~. .~.   .!7!7@@    //
//    :#@#55B@@. Y@B??G@P.5&@&PPPP@@7 .PYJY@@. B@&#P5&@P 7#@@PG7~@@JJG~ ~&@G5G&@& :@@ .^ B@? 5@G :#@B55#@@    //
//    @@!    @@.7@@YJJY&@7 5@G .. #@7 .?5YJ&@! B@Y   .@@: ^@&   .#@BJ^ .@@.   !@& :@@ .~ B@? 5@P &@!   .@@    //
//    &@J   ^@@.~@&~..:^:  5@G !^ #@!.@@: .#@! B@?    &@^ ~@&     .~G@&^@@~   ~@& .@@: . &@? 5@P #@?   ^@@    //
//    .P@&B##&@. !&&BGB&!  Y@P ~: B@~ B@PYP#@! G@?    &@: .&@##P:#BPB@B .B@#BB&@&  ?@@BB##@7 Y@P .G@&B##&@    //
//       :^:  .    .^~^..^..:.   .^~:~ ^~~: .  :.     ^^:?  ::. :::^::^55 ^~~.!@& ...^~^..:   .     :^:  .    //
//                  :???JYJ??..!Y@@@@@~#@@@P.    .:   G@@#   .. .  .5@@@&~@@& ^@& .Y?777?JJ:                  //
//                  :YJJJJJJJ^!YJYG#&G~:J??7.   ^P?P  7@@?  5?P~   .!??J:^G&B ~@& .JJJJJJJY:                  //
//                  :YJJJJJJJJJJJJ?.  ..^. .~~  :G@&  !@@7  #@G:  ^~. .^..  . .?! ^JJJJJJJY:                  //
//                  :YJJJJJJJJJJJY: .?JYY5PB5   #@@7  #@@#  !@@#   YBP5YYJ?. :7~~7JJJJJJJJY:                  //
//                   :~?JYJJJJJJJJ. ?JJJJ7^.  :B@&^ :#@@@@#: ^&@#:  .^7JJJJ? .YJJJJJJJYJ?~:                   //
//                      .:!?JYJJJ?:7JJJ7. .:!?JYY. Y@@&GG&@@5 .JYJ?!:. .!JJJ7:7JJJYJ?!:.                      //
//                          .^7JYJJJJJJ ^?JYJJJJ^ ~5P~    ~P5~ ^JJJJYJ?^ JJJJJJYJ7^.                          //
//                              :~?JYJJ!JJJJJJJJ7 ~J?.    .?J! 7JJJJJJJJ!JJYJ?~:                              //
//                                 .:!?YYJJJJJJJJ7^?J?!..!?J?^7JJJJJJJJYY?!:.                                 //
//                                     .^7JJJJJJJJJJJJY^^YJJJJJJJJJJJJ7^.                                     //
//                                         .~7JYJJJJJJY::YJJJJJJYJ7~.                                         //
//                                            .:!?JYJJY::YJJYJ?!:.                                            //
//                                                .^7JY^^YJ7^.                                                //
//                                                    :..:                                                    //
//                                                                                                            //
//                                                                                                            //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract DSQD is ERC721Creator {
    constructor() ERC721Creator("defiantsquid", "DSQD") {}
}

