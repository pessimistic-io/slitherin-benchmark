
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: 8xx8
/// @author: manifold.xyz

import "./ERC1155Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                  █████████╠                                                          //
//                                           ╠╬██████████████▀▀▀▀▀▀▀╙╙└└└└   ╙▀███╠                                                     //
//                                ║████▀▀▀▀▀▀▀╙╙╙└└─'   ,,▄▄▄▄▄▄▄███▀▀▀▀▀▀▀▀▌▐██▄╙▀███╠                                                 //
//                                ║▌▄▄▄▄▄▄φÆ█▀▀▀▀▀▀▀╙╙╙╙└└─'               j▌▐██████▄╙▀███                                              //
//                                ╟▌█                                ▄██▄  j▌▐██████████▄█                                              //
//                                ╟▌█               ╓█▀╙▀▄ ▀ ╟\╙▌⌐▌ █└  ╙█ j▌▐████████████                                              //
//                                ╟▌█              ▐█⌐   █  ▌▌ [╟▓⌐ ╟▄  ▄█ ]O▐████████████                                              //
//                                ╟▌█  ▄▀╙█▀ █.█ █   ▀███Γ  ╙⌐ │ ╝ ⌐ ╙██▌  ▐µ▐████████████                                              //
//                                ╫▌█  █  █b █ █ █   ▄█▀██  ▐█ ] █µΓ╔█╙└╙█▄▐⌐▐████████████                                              //
//                                ▓▌█  ▄▀▀─Γ        █▌   ╙█ ▌▐µj▐╘█|█    ▐█▐⌐▐████████████                                              //
//                                █▌█  ╙█▀▀█        █▌   █▌╓▌ █ █j╙▌╙█▄▄▄█Γ▐ ▐████████████                                              //
//                                █▌█  ╫ç,,╩         ╙▀▀▀▀                 ▐ ▐████████████                                              //
//                                █▌█                                      ▐ ▐████████████                                              //
//                                █▌▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀╙╙╙╙╙╙╙╙└╙╙╙╙╙ ╙▀▀██████████                                              //
//                                ██████████████████████████████████████████████▄▄▄▄│╙▀▀▀█                                              //
//                                ██╠╠╠╠╠╠╠╠╠╠╠╠╠╠╠╠╠╠╠╠╠╠╢╢╢╢╢╣╣╣╣╣╣╣▒▒▒▒▒██╠╠╠╠╠╠███████                                              //
//                                ██▒▒▒▒▒▒▒▒▒╢███████████████████▒▒▒▒▒▒▒▒▒▒██▒▒▒▒╣╣╣╣╣╣▒╣█                                              //
//                                ██▒▒▒▒▒▒▒▒▒╢█ φφφφφO╟▌ #####φ╟█▒▒▒▒▒▒▒▒▒▒██▒▒▒▒█░╬╬╬╬╫▒█                                              //
//                                ██▒▒▒▒▒▒▒▒▒╢█ ╬╬╬╬╬░╟▌ ╬╬╬╬╬╠╟█▒▒▒▒▒▒▒▒▒▒██▒▒▒▒█▒╬╬╬╬╫▒█                                              //
//                                ██▒▒▒▒▒▒▒▒▒╢█ ╬╬╬╬╬░╟▌ ╬╬╬╬╬╠╟█▒▒▒▒▒▒▒▒▒▒██▒▒▒▒█▒╬╬╬╬╫▒█                                              //
//                                ██▒▒▒▒▒▒▒▒▒╢█ ╬╬╬╬╬░╟▌ ╬╬╬╬╬╠╟█▒▒▒▒▒▒▒▒▒▒██▒▒▒▒█▒╬╬╬╬╫▒█                                              //
//                                ██▒▒▒▒▒▒▒▒▒╢█ ╬╬╬╬╬░╟▌ ╬╬╬╬╬╠╟█▒▒▒▒▒▒▒▒▒▒██▒▒▒▒█▒╬╬╬╬╫▒█                                              //
//                                ██▒▒▒▒▒▒▒▒▒╢█ ╬╬╬╬╬░╟▌ ╬╬╬╬╬╠╟█▒▒▒▒▒▒▒▒▒▒██▒▒▒▒█▒╬╬╬╬╫▒█                                              //
//                                ██▒▒▒▒▒▒▒▒▒╢█ ╝╝╝╝╝⌐╟▌ ╝╝╝╝╝╩╟█▒▒▒▒▒▒▒▒▒▒██▒▒▒▒█▒╬╬╬╬╫▒█                                              //
//                               ╣██▒▒▒▒▒╣▒▒▒║███████████████████▒▒▒▒▒▒▒▒╣▒██▒▒▒▒███████▒█                                              //
//                               ╣██╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬██╬╣███████████                                              //
//                               ╢████████████████████████████████████████████████████████                                              //
//                               ╙▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀                                              //
//                                 gm8xx8gm8xx8gm8xx8gm8xx8gm8xx8gm8xx8gm8xx8gm8xx8gm8xx8                                               //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//                                                                                                                                      //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract gm8xx8 is ERC1155Creator {
    constructor() ERC1155Creator() {}
}

