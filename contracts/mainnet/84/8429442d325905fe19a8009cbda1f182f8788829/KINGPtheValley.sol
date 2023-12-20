
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: kingPIXELpush - Another Day in the Valley
/// @author: manifold.xyz

import "./ERC721Creator.sol";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                                    //
//                                                                                                                                                                    //
//    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //     __  __     __     __   __     ______                                                                                                               //    //
//    //    /\ \/ /    /\ \   /\ "-.\ \   /\  ___\                                                                                                              //    //
//    //    \ \  _"-.  \ \ \  \ \ \-.  \  \ \ \__ \                                                                                                             //    //
//    //     \ \_\ \_\  \ \_\  \ \_\\"\_\  \ \_____\                                                                                                            //    //
//    //      \/_/\/_/   \/_/   \/_/ \/_/   \/_____/                                                                                                            //    //
//    //                                                                                                                                                        //    //
//    //     ______   __  __     __         ______   __  __     ______     __  __                                                                               //    //
//    //    /\  == \ /\_\_\_\   /\ \       /\  == \ /\ \/\ \   /\  ___\   /\ \_\ \                                                                              //    //
//    //    \ \  _-/ \/_/\_\/_  \ \ \____  \ \  _-/ \ \ \_\ \  \ \___  \  \ \  __ \                                                                             //    //
//    //     \ \_\     /\_\/\_\  \ \_____\  \ \_\    \ \_____\  \/\_____\  \ \_\ \_\                                                                            //    //
//    //      \/_/     \/_/\/_/   \/_____/   \/_/     \/_____/   \/_____/   \/_/\/_/                                                                            //    //
//    //                                                                                                                                                        //    //
//    //           _                                                                                                                                            //    //
//    //         _n_|_|_,_                                                                                                                                      //    //
//    //        |===.-.===|                                                                                                                                     //    //
//    //        |  ((_))  |                                                                                                                                     //    //
//    //        '==='-'==='                                                                                                                                     //    //
//    //       @kingpixelpush                                                                                                                                   //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                              //
//                ▄▄▄█████▓ ██░ ██ ▓█████     ██▒   █▓ ▄▄▄       ██▓     ██▓    ▓█████▓██   ██▓                                                                       //
//                ▓  ██▒ ▓▒▓██░ ██▒▓█   ▀    ▓██░   █▒▒████▄    ▓██▒    ▓██▒    ▓█   ▀ ▒██  ██▒                                                                       //
//                ▒ ▓██░ ▒░▒██▀▀██░▒███       ▓██  █▒░▒██  ▀█▄  ▒██░    ▒██░    ▒███    ▒██ ██░                                                                       //
//                ░ ▓██▓ ░ ░▓█ ░██ ▒▓█  ▄      ▒██ █░░░██▄▄▄▄██ ▒██░    ▒██░    ▒▓█  ▄  ░ ▐██▓░                                                                       //
//                  ▒██▒ ░ ░▓█▒░██▓░▒████▒      ▒▀█░   ▓█   ▓██▒░██████▒░██████▒░▒████▒ ░ ██▒▓░                                                                       //
//                  ▒ ░░    ▒ ░░▒░▒░░ ▒░ ░      ░ ▐░   ▒▒   ▓▒█░░ ▒░▓  ░░ ▒░▓  ░░░ ▒░ ░  ██▒▒▒                                                                        //
//                     ░     ▒ ░▒░ ░ ░ ░  ░      ░ ░░    ▒   ▒▒ ░░ ░ ▒  ░░ ░ ▒  ░ ░ ░  ░▓██ ░▒░                                                                       //
//                      ░       ░  ░░ ░   ░           ░░    ░   ▒     ░ ░     ░ ░      ░   ▒ ▒ ░░                                                                     //
//                         ░  ░  ░   ░  ░         ░        ░  ░    ░  ░    ░  ░   ░  ░░ ░                                                                             //
//                                    ░                                    ░ ░                                                                                        //
//                                                                                                                                   //                               //
//    //                                                                                                                                                        //    //
//    //    ██████╗  ██████╗ ██████╗ ██████╗                                                                                                                    //    //
//    //    ╚════██╗██╔═████╗╚════██╗╚════██╗                                                                                                                   //    //
//    //     █████╔╝██║██╔██║ █████╔╝ █████╔╝                                                                                                                   //    //
//    //    ██╔═══╝ ████╔╝██║██╔═══╝ ██╔═══╝                                                                                                                    //    //
//    //    ███████╗╚██████╔╝███████╗███████╗                                                                                                                   //    //
//    //    ╚══════╝ ╚═════╝ ╚══════╝╚══════╝                                                                                                                   //    //
//    //                                                                                                                                                        //    //
//    //    .  . .-. .-. .-.   . . . .-. .   .     .-. .-.   .-. .-. . . .-. .-. .   .-. .-.                                                                    //    //
//    //    |\/| | | |(  |-    | | |  |  |   |     |(  |-    |(  |-  | | |-  |-| |   |-  |  )                                                                   //    //
//    //    '  ` `-' ' ' `-'   `.'.' `-' `-' `-'   `-' `-'   ' ' `-' `.' `-' ` ' `-' `-' `-' . . .                                                              //    //
//    //                                                                                                                                                        //    //
//    //    -------------------------------------------------------------------------,                                                                          //    //
//    //    [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [                                                                           //    //
//    //    -----------------------------------------------------------------------/                                                                            //    //
//    //          \|/ | O -   ^^         |                  |           _   _     |                                                                             //    //
//    //         --O--|/ \        O  ^^  |   ^^   |||||     |     ___  ( ) ( )   _/                                                                             //    //
//    //     /\   /|\ |         --|--    | ^^     |O=O|     |_ __/_|_\,_|___|___/                                                                               //    //
//    //    /  \/\    |~~~~~~~~~~~|~~~~~~|        ( - )     | `-O---O-'       |                                                                                 //    //
//    //      /\  \/\_|          / \     |       .-~~~-.    | -- -- -- -- -- /                                                                                  //    //
//    //     /  /\ \  |         '   `    |      //| o |\\   |______________ |                                                                                   //    //
//    //    --------------------------------------------------------------_/                                                                                    //    //
//    //    [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] [] ['                                                                                      //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    //                                                                                                                                                        //    //
//    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////    //
//                                                                                                                                                                    //
//                                                                                                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract KINGPtheValley is ERC721Creator {
    constructor() ERC721Creator("kingPIXELpush - Another Day in the Valley", "KINGPtheValley") {}
}

