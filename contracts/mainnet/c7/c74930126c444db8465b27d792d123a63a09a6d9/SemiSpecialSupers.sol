
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title: SemiSpecialSupers
/// @author: manifold.xyz

import "./ERC721Creator.sol";

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                                                                                              //
//                                                                                      @@@@  @@@@@                                                             //
//                                                                                    @@@@@@  @@@@@,                                                            //
//                                                                        @@@@@@     @@@@@@@  @@@@@&                                                            //
//                                                                 @@@@@  @@@@@@@   @@@@@@@@  @@@@@@                                                            //
//                                                           #@@@@@@@@@@  @@@@@@@@  @@@@@@@@  @@@@@@                                                            //
//                                                  *@@@@@@   @@@@@@      @@@@@@@@@@@@@@@@@@. @@@@@@                                                            //
//                                              @@@@@@@@@@@   @@@@@       @@@@@@@@@@@@*@@@@@# @@@@@@                                                            //
//                                              @@@@@@        @@@@@*      @@@@@@@@@@@@ @@@@@@ %@@@@@                                                            //
//                                              @@@@@@        @@@@@@@@@@. @@@@@@  @@@  @@@@@@  @@@@@                                                            //
//                                              @@@@@@        @@@@@@@@@@& %@@@@@   @   @@@@@@  @@@@@,               @@@@.                                       //
//                                              /@@@@@@@@@@@& @@@@@@      ,@@@@@       %@@@@@  @@@@@@              @@@@@&                                       //
//                                               @@@@@@@@@@@@ @@@@@@       @@@@@        @@@@@         @@@@@@@@     @@@@@@                                       //
//                                               @@@@  @@@@@@ ,@@@@@   @@  @@@@@.              @     @@@@@@@@@     @@@@@@                                       //
//                                                     (@@@@@  @@@@@@@@@@  @@@@@       ,@  @@@@@*    @@@@@@@@@@    @@@@@@                                       //
//                                                     .@@@@@  @@@@@@@@@@       /@@@@@@@@  @@@@@&    @@@@%@@@@@    @@@@@@                                       //
//                                                @@@@@@@@@@@  @@@       (, #@@@@@@@@@@@@  @@@@@@    @@@@*%@@@@@   @@@@@@                                       //
//                                                @@@@@@@@@       %@@@@@@@% @@@@@@  @@@@@. @@@@@@   &@@@@  @@@@@   @@@@@@                                       //
//                                                @&       /#   @@@@@@@@@@# &@@@@@  (@@    @@@@@@   @@@@@  @@@@@@  /@@@@@/     /                                //
//                                                  &@@@@@@@@@& @@@@@@      .@@@@@         @@@@@@   @@@@@   @@@@@   @@@@@@@@@@@,                                //
//                                           @@  @@@@@@@@@@@@@@ @@@@@@       @@@@@         /@@@@@   @@@@@@@@@@@@@@  @@@@@@@@@@@                                 //
//                                    @@@@@@@@@  @@@@@@   @@@@@ ,@@@@@ ,@@@  @@@@@          @@@@@   @@@@@@@  @@@@@  @@@@@@                                      //
//                                  @@@@@@@@@@   (@@@@@   @@@@@  @@@@@@@@@@  @@@@@,         @@@@@# #@@@@@    @@@@@@       ,                                     //
//                                  @@@@@         @@@@@   @@@@@  @@@@@@@/    @@@@@%         @@@@@@ @@@@@@          *@@@@@@@                                     //
//                                  @@@@@*        @@@@@   @@@@@  @@@@@%      @@@@@@  @@@@@  @@@@@@ @@           @@@@@@@@@@@                                     //
//                                  @@@@@&  %@@   @@@@@,@@@@@@@  @@@@@@      @@@@@@@@@@@@@  @@       #@@@@@@@@  @@@@@@                                          //
//                                  @@@@@@@@@@@@  @@@@@@@@@@@.   @@@@@@@@@@@  @@@@@@@@&       % .@@@@@@@@@@@@@  @@@@@@                                          //
//                                  @@@@@@@@@@@@  @@@@@@         @@@@@@@@@@@           &@@@@@@@  @@@@@   @@@@@( @@@@@@                                          //
//                                         @@@@@% @@@@@@         %@@@@@@#           *@@@@@@@@@@  @@@@@   @@@@@@ @@@@@@@@@@@@(                                   //
//                                         @@@@@@ &@@@@@                 @@@@@@@@@@  @@@@@       @@@@@#  @@@@@@ ,@@@@@@@@@@@@                                   //
//                                        &@@@@@@ *@@@@@          @@  @@@@@@@@@@@@@  @@@@@       @@@@@@@@@@@@@   *@@   @@@@@@                                   //
//                                    @@@@@@@@@@@  ,       @  @@@@@@  @@@@@   @@@@@  @@@@@# (@@  @@@@@@@@@@@@@@        @@@@@@                                   //
//                                    @@@@@@.         @@@@@@  (@@@@@  @@@@@,  @@@@@  @@@@@@@@@@/ @@@@@@  .@@@@@        @@@@@@                                   //
//                                           @@@@@@@  @@@@@@   @@@@@  @@@@@&  @@@@@, @@@@@@@@.   (@@@@@   @@@@@   @@@@@@@@@@@                                   //
//                                       @@@@@@@@@@@   @@@@@   @@@@@  @@@@@@  @@@@@& @@@@@@      .@@@@@   @@@@@.  @@@@@@@&                                      //
//                                       @@@@@&        @@@@@   @@@@@. @@@@@@ @@@@@@@ @@@@@@       @@@@@   @@@@@@  %                                             //
//                                       @@@@@#        @@@@@   @@@@@& @@@@@@@@@@@@   .@@@@@/@@@@  @@@@@,  @#                                                    //
//                                       @@@@@@        @@@@@/  @@@@@@ *@@@@@          @@@@@@@@@@  @@(                                                           //
//                                       @@@@@@@@@@@@  @@@@@@  @@@@@@  @@@@@          @@@@@@@/                                                                  //
//                                       @@@@@@@@@@@@. @@@@@@  @@@@@@  @@@@@          *                                                                         //
//                                        @@@   @@@@@@ @@@@@@  .@@@@@  @@@@@/                                                                                   //
//                                              @@@@@@ #@@@@@@@@@@@@@  @                                                                                        //
//                                              @@@@@@  @@@@@@@@@@@                                                                                             //
//                                         @@@@@@@@@@@                                                                                                          //
//                                         @@@@@@@@                                                                                                             //
//                                         @                                                                                                                    //
//                                                                                                                                                              //
//                                                                                                                                                              //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


contract SemiSpecialSupers is ERC721Creator {
    constructor() ERC721Creator("SemiSpecialSupers", "SemiSpecialSupers") {}
}

